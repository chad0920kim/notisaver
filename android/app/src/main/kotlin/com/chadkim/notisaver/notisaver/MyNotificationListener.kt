package com.chadkim.notisaver.notisaver

import android.app.Notification
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class MyNotificationListener : NotificationListenerService() {

    companion object {
        var onNotificationReceived: ((packageName: String, title: String, content: String, timestamp: Long) -> Unit)? = null
    }

    private lateinit var dbHelper: DatabaseHelper

    override fun onCreate() {
        super.onCreate()
        dbHelper = DatabaseHelper(this)
        Log.d("NotiSaver", "Notification Listener Service Created")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        
        // 내 앱 자체의 알림은 기록하지 않음
        if (packageName == this.packageName) return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        // 제목과 내용이 모두 없으면 스킵
        if (title.isEmpty() && text.isEmpty()) return

        val timestamp = sbn.postTime

        // ANR 방지를 위해 백그라운드 쓰레드에서 DB 쓰기 작업 실행
        Thread {
            try {
                val db = dbHelper.writableDatabase
                val values = ContentValues().apply {
                    put("package_name", packageName)
                    put("title", title)
                    put("content", text)
                    put("timestamp", timestamp)
                }
                db.insert("notification_logs", null, values)
                Log.d("NotiSaver", "Saved Notification in background: $title - $text ($packageName)")

                // Flutter 쪽으로 실시간 이벤트 전송
                onNotificationReceived?.invoke(packageName, title, text, timestamp)
            } catch (e: Exception) {
                Log.e("NotiSaver", "Error saving notification to DB: ${e.message}")
            }
        }.start()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // 필요시 알림 제거 이벤트 처리
    }

    override fun onDestroy() {
        super.onDestroy()
        // 파일 디스크립터 및 연결 누수 방지
        dbHelper.close()
        Log.d("NotiSaver", "Notification Listener Service Destroyed")
    }
}

class DatabaseHelper(context: Context) : SQLiteOpenHelper(context, "notisaver.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS notification_logs (" +
            "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "package_name TEXT NOT NULL, " +
            "title TEXT, " +
            "content TEXT, " +
            "timestamp INTEGER NOT NULL" +
            ")"
        )
    }

    // Kotlin DB 헬퍼에서도 WAL 모드 활성화 (Flutter read와 동시 작업 지원)
    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.enableWriteAheadLogging()
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // 마이그레이션이 필요할 때 구현
    }
}
