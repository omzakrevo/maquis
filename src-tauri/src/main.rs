#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;
use rusqlite::{Connection, Result, params, types::Value};
use std::sync::Mutex;
use serde::{Serialize, Deserialize};
use serde_json::Value as JsonValue;
use std::path::PathBuf;
use std::fs;

struct AppState {
    db: Mutex<Connection>,
}

#[derive(Debug, Serialize, Deserialize)]
struct QueryResult {
    columns: Vec<String>,
    rows: Vec<Vec<JsonValue>>,
}

fn convert_to_json_value(value: &rusqlite::types::Value) -> JsonValue {
    match value {
        Value::Null => JsonValue::Null,
        Value::Integer(i) => JsonValue::Number((*i).into()),
        Value::Real(f) => {
            let n = serde_json::Number::from_f64(*f);
            match n {
                Some(n) => JsonValue::Number(n),
                None => JsonValue::Null,
            }
        }
        Value::Text(s) => JsonValue::String(s.clone()),
        _ => JsonValue::Null,
    }
}

#[tauri::command]
async fn execute_query(
    state: tauri::State<'_, AppState>,
    sql: String,
    params: Vec<String>,
) -> Result<QueryResult, String> {
    let conn = state.db.lock().map_err(|_| "Failed to lock database")?;
    
    let mut stmt = conn.prepare(&sql).map_err(|e| format!("Failed to prepare statement: {}", e))?;
    
    let column_names: Vec<String> = stmt
        .column_names()
        .into_iter()
        .map(String::from)
        .collect();
    
    let params_values: Vec<&str> = params.iter().map(|s| s.as_str()).collect();

    let rows = stmt
        .query_map(rusqlite::params_from_iter(params_values.iter()), |row| {
            let mut values = Vec::new();
            for i in 0..row.column_count() {
                let value: rusqlite::types::Value = row.get_unwrap(i);
                values.push(convert_to_json_value(&value));
            }
            Ok(values)
        })
        .map_err(|e| format!("Failed to execute query: {}", e))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Failed to collect results: {}", e))?;

    Ok(QueryResult {
        columns: column_names,
        rows,
    })
}

#[tauri::command]
async fn execute_statement(
    state: tauri::State<'_, AppState>,
    sql: String,
    params: Vec<String>,
) -> Result<(), String> {
    let conn = state.db.lock().map_err(|_| "Failed to lock database")?;
    
    let params_values: Vec<&str> = params.iter().map(|s| s.as_str()).collect();

    conn.execute(&sql, rusqlite::params_from_iter(params_values.iter()))
        .map_err(|e| format!("Failed to execute statement: {}", e))?;
    Ok(())
}

fn main() {
    // Créer le dossier data s'il n'existe pas
    let app_dir = tauri::api::path::app_dir(&tauri::Config::default())
        .expect("Failed to get app dir");
    fs::create_dir_all(&app_dir).expect("Failed to create app directory");
    
    let db_path = app_dir.join("maquis.db");
    let conn = Connection::open(&db_path).expect("Failed to open database");
    
    // Enable foreign keys and WAL mode for better concurrency
    conn.execute_batch("
        PRAGMA foreign_keys = ON;
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA busy_timeout = 5000;
    ").expect("Failed to set database pragmas");
    
    tauri::Builder::default()
        .manage(AppState {
            db: Mutex::new(conn),
        })
        .invoke_handler(tauri::generate_handler![execute_query, execute_statement])
        .setup(|app| {
            #[cfg(debug_assertions)]
            {
                let window = app.get_window("main").unwrap();
                window.open_devtools();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}