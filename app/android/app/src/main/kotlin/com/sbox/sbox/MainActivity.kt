package com.sbox.sbox

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Canal nativo de espacio libre en disco — usado antes de aceptar un
    // archivo grande, contraparte del canal "sbox/diskspace" en Linux
    // (my_application.cc, vía statvfs).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sbox/diskspace")
            .setMethodCallHandler { call, result ->
                if (call.method == "getFreeBytes") {
                    val path = call.arguments as? String
                    try {
                        result.success(StatFs(path).availableBytes)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
