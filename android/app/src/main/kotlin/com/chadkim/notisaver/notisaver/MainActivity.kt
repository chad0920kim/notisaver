package com.chadkim.notisaver.notisaver

import android.content.Intent
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val PERMISSION_CHANNEL = "com.chadkim.notisaver/permission"
    private val EVENT_CHANNEL = "com.chadkim.notisaver/events"
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. 권한 체크 및 설정창 유도를 위한 MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(isNotificationServiceEnabled())
                }
                "requestPermission" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // 2. 실시간 알림 수신을 위한 EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    
                    // 리스너가 연결된 경우에만 콜백 바인딩
                    MyNotificationListener.onNotificationReceived = { packageName, title, content, timestamp ->
                        runOnUiThread {
                            // EventSink는 오직 메인 UI 스레드에서만 데이터를 받아야 하므로 runOnUiThread 사용
                            val data = mapOf(
                                "packageName" to packageName,
                                "title" to title,
                                "content" to content,
                                "timestamp" to timestamp
                            )
                            eventSink?.success(data)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    // 메모리 누수 및 Stale EventSink 방지를 위해 연결 해제 시 콜백 null 처리
                    eventSink = null
                    MyNotificationListener.onNotificationReceived = null
                }
            }
        )
    }

    // 알림 접근 권한이 켜져 있는지 확인하는 함수
    private fun isNotificationServiceEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        if (!flat.isNullOrEmpty()) {
            val names = flat.split(":")
            for (name in names) {
                val cn = android.content.ComponentName.unflattenFromString(name)
                if (cn != null && cn.packageName == pkgName) {
                    return true
                }
            }
        }
        return false
    }
}
