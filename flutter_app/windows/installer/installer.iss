; Installateur Windows de CAISSE PRO (Inno Setup 6).
; Compilé par .github/workflows/windows.yml ou par build_windows.bat.
#ifndef AppVersion
  #define AppVersion "0.6.2"
#endif

[Setup]
AppId={{68935CAF-8C8D-471A-84F4-293E6D1833A7}
AppName=CAISSE PRO
AppVersion={#AppVersion}
AppPublisher=OMZAKREVO INFORMATIQUE
DefaultDirName={autopf}\CAISSE PRO
DefaultGroupName=CAISSE PRO
OutputDir=..\..\dist
OutputBaseFilename=CaissePro_V{#AppVersion}_Windows_installation
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\caisse_pro.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CAISSE PRO"; Filename: "{app}\caisse_pro.exe"
Name: "{group}\Désinstaller CAISSE PRO"; Filename: "{uninstallexe}"
Name: "{autodesktop}\CAISSE PRO"; Filename: "{app}\caisse_pro.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\caisse_pro.exe"; Description: "Lancer CAISSE PRO"; Flags: nowait postinstall skipifsilent
