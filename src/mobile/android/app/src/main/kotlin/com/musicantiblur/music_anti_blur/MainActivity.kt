package com.musicantiblur.music_anti_blur

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val safChannel = "music_anti_blur/saf"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannel).setMethodCallHandler { call, result ->
            if (call.method == "takePersistable") {
                val raw = call.argument<String>("uri")
                if (raw.isNullOrEmpty()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    contentResolver.takePersistableUriPermission(
                        Uri.parse(raw),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
