package com.hermes.hermes_chat

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = HermesApplication.ENGINE_ID
}
