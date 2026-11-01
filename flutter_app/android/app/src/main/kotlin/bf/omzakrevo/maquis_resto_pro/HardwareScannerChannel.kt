package bf.omzakrevo.maquis_resto_pro

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Parcel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Lecteur de codes intégré des terminaux de caisse Android (tête de lecture).
 *
 * Allumage depuis l'application, dans cet ordre :
 *  1. Sunmi     : service « com.sunmi.scanner » (AIDL IScanInterface) → stop() puis scan()
 *  2. Urovo et clones : classe système android.device.ScanManager → openScanner() + startDecode()
 *  3. Zebra     : DataWedge SOFT_SCAN_TRIGGER = START_SCANNING
 *  4. Honeywell : ACTION_CONTROL_SCANNER, EXTRA_SCAN = true
 *  5. Newland   : nlscan.action.SCANNER_TRIG
 * Réception : diffusions ci-dessous, ou « sortie clavier » captée par un champ texte Flutter.
 */
class HardwareScannerChannel(private val context: Context, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    private var sunmi: IBinder? = null
    private var sunmiBinding = false
    private val sunmiWaiters = mutableListOf<(IBinder?) -> Unit>()

    private var urovo: Any? = null
    private var lastMethod = "aucun"
    private var lastError: String? = null
    private var lastCode: String? = null

    private val resultActions = mapOf(
        "com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED" to listOf("data"),
        "com.imin.scanner.api.RESULT_ACTION" to listOf("decode_data_str", "decode_data"),
        "android.intent.ACTION_DECODE_DATA" to listOf("barcode_string", "barcode"),
        "nlscan.action.SCANNER_RESULT" to listOf("SCAN_BARCODE1"),
        "com.honeywell.decode.intent.action.EDIT_DATA" to listOf("data"),
        // lecteurs génériques des terminaux chinois (iData, Chainway, clones Urovo…)
        "android.intent.action.SCANRESULT" to listOf("value"),
        "com.scanner.broadcast" to listOf("data"),
        "com.android.server.scannerservice.broadcast" to listOf("scannerdata"),
        "scan.rcv.message" to listOf("barocode", "barcode"),
        // action libre à configurer dans l'appli du lecteur (sortie « intent / broadcast »)
        "bf.omzakrevo.SCAN" to listOf("data", "barcode_string", "com.symbol.datawedge.data_string"),
    )

    private val sunmiConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            sunmi = service
            sunmiBinding = false
            flushSunmi(service)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            sunmi = null
        }

        override fun onBindingDied(name: ComponentName?) {
            sunmi = null
            sunmiBinding = false
        }

        override fun onNullBinding(name: ComponentName?) {
            sunmiBinding = false
            flushSunmi(null)
        }
    }

    init {
        MethodChannel(messenger, "bf.omzakrevo/hw_scanner").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(info())
                "diagnose" -> withSunmi { b -> result.success(diagnose(b)) }
                "start" -> start { r -> result.success(r) }
                "stop" -> {
                    stop(); result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "bf.omzakrevo/hw_scanner/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                register()
            }

            override fun onCancel(arguments: Any?) {
                unregister()
                sink = null
            }
        })
    }

    // ---------------------------------------------------------------- détection

    private fun deviceText() = (Build.MANUFACTURER + " " + Build.BRAND + " " + Build.MODEL + " " + Build.DEVICE).lowercase()

    private fun sunmiIntent() = Intent("com.sunmi.scanner.IScanInterface").setPackage("com.sunmi.scanner")

    private fun hasSunmiService(): Boolean = try {
        context.packageManager.queryIntentServices(sunmiIntent(), 0).isNotEmpty()
    } catch (e: Exception) {
        false
    }

    private fun urovoClass(): Class<*>? = try {
        Class.forName("android.device.ScanManager")
    } catch (e: Throwable) {
        null
    }

    private fun brand(): String {
        val m = deviceText()
        return when {
            m.contains("sunmi") || hasSunmiService() -> "sunmi"
            m.contains("zebra") || m.contains("symbol") -> "zebra"
            m.contains("honeywell") -> "honeywell"
            m.contains("newland") || m.contains("nlscan") -> "newland"
            m.contains("imin") -> "imin"
            m.contains("urovo") || urovoClass() != null -> "urovo"
            else -> "other"
        }
    }

    private fun info(): Map<String, Any> {
        val b = brand()
        return mapOf(
            "brand" to b,
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "softTrigger" to (b in listOf("sunmi", "urovo", "zebra", "honeywell", "newland")),
        )
    }

    private fun diagnose(sunmiBinder: IBinder?): Map<String, Any?> {
        var sunmiModel: Int? = null
        var sunmiErr: String? = null
        if (sunmiBinder != null) {
            try {
                sunmiModel = sunmiInt(SUNMI_GET_MODEL)
            } catch (e: Exception) {
                sunmiErr = e.toString()
            }
        }
        val pm = context.packageManager
        val scanApps = listOf(
            "com.sunmi.scanner", "com.imin.scanner", "com.ubx.scanwedge", "android.device.scanner",
            "com.symbol.datawedge", "com.honeywell.ezconfig", "com.nlscan.scanner", "com.android.scanner",
        ).filter {
            try {
                pm.getPackageInfo(it, 0); true
            } catch (e: Exception) {
                false
            }
        }
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brandBuild" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "detected" to brand(),
            "sunmiService" to hasSunmiService(),
            "sunmiConnected" to (sunmiBinder != null),
            // 100 = pas de tête de lecture (caméra seulement)
            "sunmiModel" to sunmiModel,
            "sunmiError" to sunmiErr,
            "urovoScanManager" to (urovoClass() != null),
            "scannerApps" to scanApps.joinToString(", "),
            "scanPackages" to scanPackages(),
            "lastMethod" to lastMethod,
            "lastError" to lastError,
            "lastCode" to lastCode,
        )
    }

    /** Applications et services installés dont le nom évoque un lecteur (pour identifier le pilote). */
    private fun scanPackages(): String = try {
        val words = listOf("scan", "barcode", "decode", "wedge", "scanner")
        val pm = context.packageManager
        @Suppress("DEPRECATION")
        val pkgs = pm.getInstalledPackages(android.content.pm.PackageManager.GET_SERVICES or android.content.pm.PackageManager.GET_RECEIVERS)
        pkgs.mapNotNull { p ->
            val parts = mutableListOf<String>()
            if (words.any { p.packageName.contains(it, true) }) parts.add(p.packageName)
            p.services?.filter { sv -> words.any { sv.name.contains(it, true) } }?.forEach { parts.add("service " + it.name) }
            p.receivers?.filter { rc -> words.any { rc.name.contains(it, true) } }?.forEach { parts.add("receiver " + it.name) }
            if (parts.isEmpty()) null else "${p.packageName}: " + parts.distinct().joinToString(" | ")
        }.take(25).joinToString("\n")
    } catch (e: Throwable) {
        "liste impossible : $e"
    }

    // ---------------------------------------------------------------- Sunmi

    private fun withSunmi(done: (IBinder?) -> Unit) {
        if (!hasSunmiService()) return done(null)
        sunmi?.let { return done(it) }
        sunmiWaiters.add(done)
        if (!sunmiBinding) {
            sunmiBinding = true
            val ok = try {
                context.bindService(sunmiIntent(), sunmiConnection, Context.BIND_AUTO_CREATE)
            } catch (e: Exception) {
                lastError = "bindService : $e"; false
            }
            if (!ok) {
                sunmiBinding = false
                lastError = lastError ?: "bindService a refusé la connexion au service de scan Sunmi"
                flushSunmi(null)
                return
            }
        }
        // ne jamais bloquer l'appelant si le service ne répond pas
        main.postDelayed({ if (sunmi == null) flushSunmi(null) }, 2500)
    }

    private fun flushSunmi(b: IBinder?) {
        val list = sunmiWaiters.toList()
        sunmiWaiters.clear()
        list.forEach { it(b) }
    }

    /** Même encodage que le code AIDL généré, sans fichier .aidl. */
    private fun sunmiVoid(code: Int) {
        val b = sunmi ?: return
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        try {
            data.writeInterfaceToken(SUNMI_DESCRIPTOR)
            b.transact(code, data, reply, 0)
            reply.readException()
        } finally {
            data.recycle(); reply.recycle()
        }
    }

    private fun sunmiInt(code: Int): Int {
        val b = sunmi ?: return -1
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        try {
            data.writeInterfaceToken(SUNMI_DESCRIPTOR)
            b.transact(code, data, reply, 0)
            reply.readException()
            return reply.readInt()
        } finally {
            data.recycle(); reply.recycle()
        }
    }

    // ---------------------------------------------------------------- allumage

    private fun start(done: (Map<String, Any?>) -> Unit) {
        lastError = null
        val b = brand()
        if (b == "sunmi") {
            withSunmi { binder ->
                if (binder == null) {
                    lastMethod = "Sunmi : service de scan injoignable"
                    done(result(false))
                    return@withSunmi
                }
                try {
                    // La doc Sunmi associe scan() et stop() : on arrête une lecture en cours puis on relance.
                    sunmiVoid(SUNMI_STOP)
                    sunmiVoid(SUNMI_SCAN)
                    lastMethod = "Sunmi : scan()"
                    done(result(true))
                } catch (e: Exception) {
                    lastMethod = "Sunmi : scan()"
                    lastError = e.toString()
                    done(result(false))
                }
            }
            return
        }
        val ok = try {
            when {
                urovoClass() != null -> startUrovo()
                b == "zebra" -> {
                    context.sendBroadcast(Intent("com.symbol.datawedge.api.ACTION").putExtra("com.symbol.datawedge.api.SOFT_SCAN_TRIGGER", "START_SCANNING"))
                    lastMethod = "Zebra DataWedge : START_SCANNING"; true
                }
                b == "honeywell" -> {
                    context.sendBroadcast(Intent("com.honeywell.aidc.action.ACTION_CONTROL_SCANNER").putExtra("com.honeywell.aidc.extra.EXTRA_SCAN", true))
                    lastMethod = "Honeywell : ACTION_CONTROL_SCANNER"; true
                }
                b == "newland" -> {
                    context.sendBroadcast(Intent("nlscan.action.SCANNER_TRIG"))
                    lastMethod = "Newland : SCANNER_TRIG"; true
                }
                b == "imin" -> {
                    context.sendBroadcast(
                        Intent("com.imin.scanner.builtin.config")
                            .putExtra("type", 0).putExtra("broadcast", true)
                            .putExtra("broadcastAction", "com.imin.scanner.api.RESULT_ACTION")
                            .putExtra("broadcastExtraStr", "decode_data_str"),
                    )
                    lastMethod = "iMin : sortie broadcast activée (pas d'allumage logiciel)"; false
                }
                else -> {
                    lastMethod = "aucune commande connue pour ${Build.MANUFACTURER} ${Build.MODEL}"; false
                }
            }
        } catch (e: Throwable) {
            lastError = e.toString(); false
        }
        done(result(ok))
    }

    private fun startUrovo(): Boolean {
        val cls = urovoClass() ?: return false
        val sm = urovo ?: cls.getDeclaredConstructor().newInstance().also { urovo = it }
        try {
            cls.getMethod("openScanner").invoke(sm)
        } catch (_: Throwable) {
        }
        try {
            cls.getMethod("stopDecode").invoke(sm)
        } catch (_: Throwable) {
        }
        val r = cls.getMethod("startDecode").invoke(sm)
        lastMethod = "ScanManager système (Urovo et compatibles) : startDecode()"
        return r != false
    }

    private fun stop() {
        try {
            when {
                sunmi != null -> sunmiVoid(SUNMI_STOP)
                urovo != null -> urovoClass()?.getMethod("stopDecode")?.invoke(urovo)
                brand() == "zebra" -> context.sendBroadcast(
                    Intent("com.symbol.datawedge.api.ACTION").putExtra("com.symbol.datawedge.api.SOFT_SCAN_TRIGGER", "STOP_SCANNING"),
                )
                brand() == "honeywell" -> context.sendBroadcast(
                    Intent("com.honeywell.aidc.action.ACTION_CONTROL_SCANNER").putExtra("com.honeywell.aidc.extra.EXTRA_SCAN", false),
                )
            }
        } catch (_: Throwable) {
        }
    }

    private fun result(triggered: Boolean) = mapOf("triggered" to triggered, "method" to lastMethod, "error" to lastError)

    // ---------------------------------------------------------------- réception

    private fun register() {
        if (receiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                val i = intent ?: return
                val keys = resultActions[i.action] ?: return
                var value: String? = null
                for (k in keys) {
                    value = i.getStringExtra(k)
                    if (value.isNullOrBlank()) i.getByteArrayExtra(k)?.let { value = String(it, Charsets.UTF_8) }
                    if (!value.isNullOrBlank()) break
                }
                val v = value?.trim()
                if (!v.isNullOrEmpty()) {
                    lastCode = "$v (${i.action})"
                    main.post { sink?.success(v) }
                }
            }
        }
        val filter = IntentFilter().apply { resultActions.keys.forEach { addAction(it) } }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(r, filter)
        }
        receiver = r
    }

    private fun unregister() {
        receiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        receiver = null
    }

    companion object {
        private const val SUNMI_DESCRIPTOR = "com.sunmi.scanner.IScanInterface"

        // Ordre des méthodes de IScanInterface : sendKeyEvent, scan, stop, getScannerModel
        private const val SUNMI_SCAN = IBinder.FIRST_CALL_TRANSACTION + 1
        private const val SUNMI_STOP = IBinder.FIRST_CALL_TRANSACTION + 2
        private const val SUNMI_GET_MODEL = IBinder.FIRST_CALL_TRANSACTION + 3
    }
}
