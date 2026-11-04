package com.mitransporte.mitransporte

import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "Compartir la app": dónde está el APK instalado y de qué tipo de procesador es.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mitransporte/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "installedApk" -> result.success(
                    mapOf(
                        "path" to applicationInfo.sourceDir,
                        "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
                    ),
                )
                else -> result.notImplemented()
            }
        }
        // QR del trabajador: clave en el Android Keystore y pantalla sin capturas (FLAG_SECURE).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mitransporte/qr").setMethodCallHandler { call, result ->
            when (call.method) {
                "publicKey", "sign" -> Thread {
                    try {
                        val value: Any = if (call.method == "publicKey") {
                            Base64.encodeToString(QrKey.publicKey(), Base64.NO_WRAP)
                        } else {
                            QrKey.sign(call.arguments as ByteArray)
                        }
                        runOnUiThread { result.success(value) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("QR_KEY", e.message, null) }
                    }
                }.start()
                "secure" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
