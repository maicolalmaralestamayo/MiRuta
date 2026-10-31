package com.mitransporte.mitransporte

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
    }
}
