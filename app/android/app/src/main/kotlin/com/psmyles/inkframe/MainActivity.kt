package com.psmyles.inkframe

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    // Photos shared from another app (ShareActivity.kt, lib/data/shared_inbox.dart).
    private var share: MethodChannel? = null
    private val copying = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        share = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "inkframe/share").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "inbox") result.success(SharedInbox.dir(this@MainActivity).path) else result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receive(intent)
    }

    override fun onDestroy() {
        copying.shutdown()
        super.onDestroy()
    }

    /** Copies shared photos into the inbox off the main thread (big files, or still downloading), then tells Dart. */
    private fun receive(intent: Intent?) {
        val uris = SharedInbox.urisIn(intent)
        if (uris.isEmpty()) return
        copying.execute {
            SharedInbox.copy(this, uris)
            runOnUiThread { share?.invokeMethod("changed", null) }
        }
    }
}
