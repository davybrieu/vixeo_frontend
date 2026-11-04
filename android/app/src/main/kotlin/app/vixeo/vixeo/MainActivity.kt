package app.vixeo.vixeo

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Tells Flutter whether it runs on Android TV / Google TV (DeviceInfo.isTv).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.vixeo/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTv())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isTv(): Boolean {
        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        return uiMode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            !packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
    }
}
