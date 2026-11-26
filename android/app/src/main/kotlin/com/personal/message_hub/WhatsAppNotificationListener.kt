package com.personal.message_hub

import android.app.Notification
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

private val WHATSAPP_PACKAGES = setOf("com.whatsapp", "com.whatsapp.w4b")

/**
 * Counts incoming WhatsApp messages from their notifications.
 * Stores only (time, chat name, sender name) - never the message text.
 */
class WhatsAppNotificationListener : NotificationListenerService() {
    private lateinit var store: NotificationStore

    override fun onCreate() {
        super.onCreate()
        store = NotificationStore(applicationContext)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in WHATSAPP_PACKAGES) return
        val n = sbn.notification
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0) return // "checking for messages", calls, web
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val conversation = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()?.trim()
        if (title.isEmpty() || title.equals("WhatsApp", ignoreCase = true)) return

        val messages = messagesFrom(extras)
        if (messages.isNotEmpty()) {
            val chat = stripCount(conversation ?: title)
            for ((time, sender) in messages) {
                store.add(time, chat, sender ?: continue) // null sender = your own reply
            }
        } else if (n.category == null || n.category == Notification.CATEGORY_MESSAGE) {
            // Old-style notification: one message, "Group: Sender" or "Sender" in the title
            val parts = title.split(": ", limit = 2)
            val chat = stripCount(if (parts.size == 2) parts[0] else title)
            store.add(n.`when`, chat, if (parts.size == 2) parts[1] else title)
        }
    }

    private fun messagesFrom(extras: Bundle): List<Pair<Long, String?>> {
        @Suppress("DEPRECATION")
        val arr: Array<Parcelable> = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return emptyList()
        return arr.mapNotNull { p ->
            val b = p as? Bundle ?: return@mapNotNull null
            val time = b.getLong("time")
            val sender = b.getCharSequence("sender")?.toString()
                ?: (if (android.os.Build.VERSION.SDK_INT >= 28) {
                    @Suppress("DEPRECATION")
                    (b.getParcelable<android.app.Person>("sender_person"))?.name?.toString()
                } else null)
            if (time == 0L) null else time to sender
        }
    }

    // "Family (3 messages)" -> "Family"
    private fun stripCount(s: String) = s.replace(Regex("""\s*\(\d+[^)]*\)$"""), "").trim()
}

class NotificationStore(ctx: Context) :
    SQLiteOpenHelper(ctx, "wa_notifications.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE ev (ts INTEGER, chat TEXT, sender TEXT, UNIQUE(ts, chat, sender))")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    fun add(ts: Long, chat: String, sender: String) {
        writableDatabase.insertWithOnConflict(
            "ev", null,
            ContentValues().apply {
                put("ts", ts)
                put("chat", chat)
                put("sender", sender)
            },
            SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    fun since(ms: Long): List<Map<String, Any>> =
        readableDatabase.rawQuery("SELECT ts, chat, sender FROM ev WHERE ts >= ? ORDER BY ts", arrayOf(ms.toString()))
            .use { c ->
                val out = ArrayList<Map<String, Any>>()
                while (c.moveToNext()) out.add(mapOf("ts" to c.getLong(0), "chat" to c.getString(1), "sender" to c.getString(2)))
                out
            }

    fun clear() {
        writableDatabase.delete("ev", null, null)
    }
}
