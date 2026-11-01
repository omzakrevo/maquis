package bf.omzakrevo.maquis_resto_pro

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Impression ESC/POS vers les imprimantes thermiques Bluetooth.
 *
 *  - Bluetooth classique (SPP/RFCOMM) : 3 méthodes de connexion essayées dans l'ordre
 *    (sécurisée, non sécurisée, canal 1 par réflexion — nécessaire pour beaucoup
 *    d'imprimantes bon marché qui refusent la recherche de service SDP).
 *  - Bluetooth basse consommation (BLE) : écriture sur la caractéristique « écriture »
 *    de l'imprimante, par paquets de la taille du MTU.
 *
 * Les octets sont envoyés tels quels (aucun caractère ajouté), par paquets avec une
 * courte pause pour ne pas saturer la mémoire tampon des petites imprimantes.
 */
@SuppressLint("MissingPermission") // les autorisations sont demandées côté Dart avant chaque appel
class ThermalPrinterChannel(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "bf.omzakrevo/thermal_printer")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var socket: BluetoothSocket? = null
    private var socketAddress: String? = null
    private var socketMethod: String? = null

    init {
        channel.setMethodCallHandler(this)
    }

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> result.success(
                mapOf(
                    "supported" to (adapter != null),
                    "enabled" to (adapter?.isEnabled == true),
                    "sdk" to Build.VERSION.SDK_INT,
                ),
            )
            "bonded" -> runIo(result) { bonded() }
            "scan" -> runIo(result) { scan((call.argument<Int>("seconds") ?: 8).toLong()) }
            "print" -> {
                val address = call.argument<String>("address") ?: return result.error("args", "Adresse manquante", null)
                val bytes = call.argument<ByteArray>("bytes") ?: return result.error("args", "Données manquantes", null)
                val chunk = call.argument<Int>("chunk") ?: 256
                val delay = call.argument<Int>("delayMs") ?: 20
                runIo(result) { print(address, bytes, chunk, delay) }
            }
            "disconnect" -> runIo(result) { closeSocket(); true }
            else -> result.notImplemented()
        }
    }

    private fun runIo(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: PrinterError) {
                main.post { result.error(e.step, e.message, e.details) }
            } catch (e: SecurityException) {
                main.post { result.error("permission", "Autorisation Bluetooth manquante : ${e.message}", null) }
            } catch (e: Exception) {
                main.post { result.error("unknown", e.message ?: e.toString(), null) }
            }
        }
    }

    class PrinterError(val step: String, message: String, val details: String? = null) : Exception(message)

    private fun typeOf(d: BluetoothDevice): String = when (d.type) {
        BluetoothDevice.DEVICE_TYPE_CLASSIC -> "classic"
        BluetoothDevice.DEVICE_TYPE_LE -> "ble"
        BluetoothDevice.DEVICE_TYPE_DUAL -> "dual"
        else -> "unknown"
    }

    private fun describe(d: BluetoothDevice, bonded: Boolean) = mapOf(
        "name" to (d.name ?: ""),
        "address" to d.address,
        "type" to typeOf(d),
        "bonded" to bonded,
        "printerLike" to isPrinterLike(d),
    )

    /** Classe d'appareil « imprimante » ou nom typique d'imprimante thermique. */
    private fun isPrinterLike(d: BluetoothDevice): Boolean {
        val major = d.bluetoothClass?.majorDeviceClass
        if (major == 0x0600) return true // IMAGING (imprimantes)
        val n = (d.name ?: "").lowercase()
        return listOf("print", "pos", "mtp", "pt-", "rpp", "xp-", "goojprt", "zj", "mpt", "thermal", "58", "80", "bt-", "ql-", "ms-").any { n.contains(it) }
    }

    private fun requireAdapter(): BluetoothAdapter {
        val a = adapter ?: throw PrinterError("unsupported", "Cet appareil n'a pas de Bluetooth")
        if (!a.isEnabled) throw PrinterError("disabled", "Le Bluetooth est désactivé. Activez-le puis réessayez.")
        return a
    }

    private fun bonded(): List<Map<String, Any?>> =
        requireAdapter().bondedDevices.map { describe(it, true) }.sortedByDescending { it["printerLike"] as Boolean }

    /** Recherche des appareils à proximité (classique + BLE) pendant [seconds] secondes. */
    private fun scan(seconds: Long): List<Map<String, Any?>> {
        val a = requireAdapter()
        val found = LinkedHashMap<String, Map<String, Any?>>()
        a.bondedDevices.forEach { found[it.address] = describe(it, true) }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (intent.action == BluetoothDevice.ACTION_FOUND) {
                    val d: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    if (d != null) synchronized(found) { found.putIfAbsent(d.address, describe(d, d.bondState == BluetoothDevice.BOND_BONDED)) }
                }
            }
        }
        val le = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, r: ScanResult) {
                synchronized(found) { found.putIfAbsent(r.device.address, describe(r.device, r.device.bondState == BluetoothDevice.BOND_BONDED)) }
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_FOUND), Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_FOUND))
        }
        val scanner = a.bluetoothLeScanner
        try {
            a.startDiscovery()
            scanner?.startScan(le)
            Thread.sleep(seconds * 1000)
        } finally {
            try { scanner?.stopScan(le) } catch (_: Exception) {}
            try { a.cancelDiscovery() } catch (_: Exception) {}
            try { context.unregisterReceiver(receiver) } catch (_: Exception) {}
        }
        return synchronized(found) {
            found.values.filter { (it["name"] as String).isNotBlank() || it["bonded"] == true }
                .sortedWith(compareByDescending<Map<String, Any?>> { it["printerLike"] as Boolean }.thenByDescending { it["bonded"] as Boolean })
        }
    }

    // ------------------------------------------------------------------ impression

    private fun print(address: String, bytes: ByteArray, chunk: Int, delayMs: Int): Map<String, Any?> {
        val a = requireAdapter()
        val device = try {
            a.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            throw PrinterError("address", "Adresse Bluetooth invalide : $address")
        }
        // Une imprimante BLE pure n'accepte pas de liaison série classique.
        if (device.type == BluetoothDevice.DEVICE_TYPE_LE) {
            return printBle(device, bytes, delayMs)
        }
        try {
            return printClassic(a, device, bytes, chunk, delayMs)
        } catch (e: PrinterError) {
            // Appareil double mode (ou type inconnu) : on tente le BLE avant d'abandonner.
            if (device.type == BluetoothDevice.DEVICE_TYPE_DUAL || device.type == BluetoothDevice.DEVICE_TYPE_UNKNOWN) {
                try {
                    return printBle(device, bytes, delayMs) + mapOf("classicError" to e.message)
                } catch (_: PrinterError) {
                }
            }
            throw e
        }
    }

    private fun printClassic(a: BluetoothAdapter, device: BluetoothDevice, bytes: ByteArray, chunk: Int, delayMs: Int): Map<String, Any?> {
        // 1. Réutilise la liaison ouverte si c'est la même imprimante, sinon (re)connecte.
        var reused = socketAddress == device.address && socket?.isConnected == true
        if (!reused) connectClassic(a, device)
        try {
            writeAll(bytes, chunk, delayMs)
        } catch (e: IOException) {
            if (!reused) throw PrinterError("write", "Connexion établie mais l'envoi a échoué : ${e.message}")
            // Liaison périmée (imprimante éteinte puis rallumée) : une nouvelle tentative.
            closeSocket()
            connectClassic(a, device)
            reused = false
            try {
                writeAll(bytes, chunk, delayMs)
            } catch (e2: IOException) {
                closeSocket()
                throw PrinterError("write", "L'envoi à l'imprimante a échoué : ${e2.message}")
            }
        }
        // Laisse le temps à l'imprimante de vider sa mémoire avant tout autre envoi.
        Thread.sleep((150 + bytes.size / 25).toLong().coerceAtMost(2500))
        return mapOf("ok" to true, "transport" to "classic", "method" to socketMethod, "reused" to reused, "bytes" to bytes.size)
    }

    private fun connectClassic(a: BluetoothAdapter, device: BluetoothDevice) {
        closeSocket()
        try { a.cancelDiscovery() } catch (_: Exception) {}
        val errors = mutableListOf<String>()
        val attempts: List<Pair<String, () -> BluetoothSocket>> = listOf(
            "sécurisée" to { device.createRfcommSocketToServiceRecord(SPP) },
            "non sécurisée" to { device.createInsecureRfcommSocketToServiceRecord(SPP) },
            "canal 1" to {
                device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType).invoke(device, 1) as BluetoothSocket
            },
        )
        for ((name, create) in attempts) {
            var s: BluetoothSocket? = null
            try {
                s = create()
                s.connect()
                socket = s
                socketAddress = device.address
                socketMethod = name
                return
            } catch (e: Exception) {
                errors += "$name : ${e.message ?: e.javaClass.simpleName}"
                try { s?.close() } catch (_: Exception) {}
                Thread.sleep(350)
            }
        }
        throw PrinterError(
            "connect",
            "Impossible de se connecter à « ${device.name ?: device.address} ». Vérifiez qu'elle est allumée, appairée, et qu'aucun autre téléphone n'y est connecté.",
            errors.joinToString("\n"),
        )
    }

    private fun writeAll(bytes: ByteArray, chunk: Int, delayMs: Int) {
        val out = socket?.outputStream ?: throw IOException("pas de liaison")
        var i = 0
        val size = chunk.coerceIn(32, 4096)
        while (i < bytes.size) {
            val n = minOf(size, bytes.size - i)
            out.write(bytes, i, n)
            out.flush()
            i += n
            if (delayMs > 0 && i < bytes.size) Thread.sleep(delayMs.toLong())
        }
    }

    private fun closeSocket() {
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        socketAddress = null
        socketMethod = null
    }

    // ------------------------------------------------------------------ BLE

    private fun printBle(device: BluetoothDevice, bytes: ByteArray, delayMs: Int): Map<String, Any?> {
        closeSocket()
        val connected = CountDownLatch(1)
        val discovered = CountDownLatch(1)
        val mtuDone = CountDownLatch(1)
        var writeLatch = CountDownLatch(1)
        var mtu = 23
        var writeStatus = BluetoothGatt.GATT_SUCCESS
        var gattState = BluetoothProfile.STATE_DISCONNECTED

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                gattState = newState
                if (newState == BluetoothProfile.STATE_CONNECTED) connected.countDown()
            }
            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) = discovered.countDown()
            override fun onMtuChanged(gatt: BluetoothGatt, value: Int, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) mtu = value
                mtuDone.countDown()
            }
            override fun onCharacteristicWrite(gatt: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                writeStatus = status
                writeLatch.countDown()
            }
        }
        val gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            ?: throw PrinterError("connect", "Connexion BLE impossible")
        try {
            if (!connected.await(12, TimeUnit.SECONDS) || gattState != BluetoothProfile.STATE_CONNECTED) {
                throw PrinterError("connect", "L'imprimante BLE « ${device.name ?: device.address} » ne répond pas. Est-elle allumée et à portée ?")
            }
            if (gatt.requestMtu(185)) mtuDone.await(3, TimeUnit.SECONDS)
            gatt.discoverServices()
            if (!discovered.await(10, TimeUnit.SECONDS)) throw PrinterError("services", "L'imprimante BLE n'a pas présenté ses services")
            val target = findWritable(gatt) ?: throw PrinterError("services", "Aucune caractéristique d'écriture trouvée : cette imprimante n'est peut-être pas compatible ESC/POS")
            val noResponse = target.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
            val writeType = if (noResponse) BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE else BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            val size = (mtu - 3).coerceIn(20, 180)
            var i = 0
            while (i < bytes.size) {
                val n = minOf(size, bytes.size - i)
                val part = bytes.copyOfRange(i, i + n)
                writeLatch = CountDownLatch(1)
                val accepted = if (Build.VERSION.SDK_INT >= 33) {
                    gatt.writeCharacteristic(target, part, writeType) == BluetoothGatt.GATT_SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    target.writeType = writeType
                    @Suppress("DEPRECATION")
                    target.value = part
                    @Suppress("DEPRECATION")
                    gatt.writeCharacteristic(target)
                }
                if (!accepted) {
                    Thread.sleep(40) // file d'attente pleine : on réessaie une fois
                    if (Build.VERSION.SDK_INT >= 33) {
                        if (gatt.writeCharacteristic(target, part, writeType) != BluetoothGatt.GATT_SUCCESS) throw PrinterError("write", "L'imprimante BLE refuse les données")
                    } else {
                        @Suppress("DEPRECATION")
                        if (!gatt.writeCharacteristic(target)) throw PrinterError("write", "L'imprimante BLE refuse les données")
                    }
                }
                if (!writeLatch.await(3, TimeUnit.SECONDS) && !noResponse) throw PrinterError("write", "L'imprimante BLE ne confirme pas la réception")
                if (writeStatus != BluetoothGatt.GATT_SUCCESS) throw PrinterError("write", "Erreur d'écriture BLE (code $writeStatus)")
                i += n
                Thread.sleep(maxOf(delayMs, 8).toLong())
            }
            Thread.sleep((300 + bytes.size / 25).toLong().coerceAtMost(2500))
            return mapOf("ok" to true, "transport" to "ble", "method" to "BLE ${target.uuid.toString().substring(4, 8)}", "reused" to false, "bytes" to bytes.size)
        } finally {
            try { gatt.disconnect() } catch (_: Exception) {}
            try { gatt.close() } catch (_: Exception) {}
        }
    }

    /** Caractéristique d'écriture de l'imprimante : UUID connus d'abord, sinon la première accessible en écriture. */
    private fun findWritable(gatt: BluetoothGatt): BluetoothGattCharacteristic? {
        val all = gatt.services.flatMap { it.characteristics }
        val writable = all.filter {
            it.properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
        }
        for (known in KNOWN_WRITE) {
            writable.firstOrNull { it.uuid.toString().equals(known, ignoreCase = true) }?.let { return it }
        }
        return writable.firstOrNull { !it.uuid.toString().startsWith("00002a", ignoreCase = true) } ?: writable.firstOrNull()
    }

    companion object {
        val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        val KNOWN_WRITE = listOf(
            "49535343-8841-43f4-a8d4-ecbe34729bb3", // ISSC / Microchip (très répandu)
            "0000ff02-0000-1000-8000-00805f9b34fb",
            "00002af1-0000-1000-8000-00805f9b34fb",
            "0000ffe1-0000-1000-8000-00805f9b34fb",
            "bef8d6c9-9c21-4c9e-b632-bd58c1009f9f",
        )
    }
}
