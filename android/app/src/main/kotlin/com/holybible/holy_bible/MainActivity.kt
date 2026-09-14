package com.holybible.holy_bible

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Мост к Play Integrity: без него сервер не пустит к разбору с ИИ.
        PlayIntegrityBridge(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
