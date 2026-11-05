package app.vixeo.vixeo

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

        // Updates without a store (lib/features/updates/apk_installer.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.vixeo/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstallPackages())
                    "openInstallSettings" -> result.success(openInstallSettings())
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) result.error("bad_args", "path missing", null)
                        else result.success(install(File(path)))
                    }
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

    /** Android 8+: the person allows Vixeo to install apps once ("Installer des applis inconnues"). */
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
            )
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** Opens Android's installer on a downloaded APK, which asks the person to confirm. */
    private fun install(apk: File): Boolean {
        val updates = File(cacheDir, "updates").canonicalFile
        // Only files of our own update folder.
        if (!apk.canonicalFile.startsWith(updates) || !apk.exists()) return false
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
