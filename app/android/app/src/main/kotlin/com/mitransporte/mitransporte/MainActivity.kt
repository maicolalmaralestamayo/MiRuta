package com.mitransporte.mitransporte

import android.content.Intent
import android.os.Bundle
import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var pendingShare: String? = null

    /** Texto o enlace compartido (ACTION_SEND) o enlace geo: (ACTION_VIEW). */
    private fun sharedText(intent: Intent?): String? = when (intent?.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            intent.getStringExtra(Intent.EXTRA_SUBJECT),
            intent.getStringExtra(Intent.EXTRA_TEXT),
        ).joinToString("\n").ifBlank { null }
        Intent.ACTION_VIEW -> intent.dataString
        else -> null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingShare = sharedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val text = sharedText(intent) ?: return
        val channel = shareChannel
        if (channel != null) channel.invokeMethod("shared", text) else pendingShare = text
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Ubicación compartida desde otras apps (docs/11 §11.51).
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mitransporte/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "initial" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
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
