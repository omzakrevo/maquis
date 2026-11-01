package bf.omzakrevo.maquis_resto_pro

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var printer: ThermalPrinterChannel? = null
    private var scanner: HardwareScannerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        printer = ThermalPrinterChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        scanner = HardwareScannerChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
