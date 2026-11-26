package com.personal.message_hub

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import android.provider.Telephony

/**
 * Reads SMS/MMS metadata for statistics: date, direction, address, size.
 * Message text is used only to measure its size and is never returned.
 */
class SmsReader(private val ctx: Context) {
    private val names = HashMap<String, String?>()
    private val canReadContacts =
        ctx.checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    fun read(sinceMs: Long): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        readSms(sinceMs, out)
        readMms(sinceMs, out)
        return out
    }

    private fun readSms(sinceMs: Long, out: MutableList<Map<String, Any?>>) {
        val cols = arrayOf(Telephony.Sms.TYPE, Telephony.Sms.DATE, Telephony.Sms.ADDRESS, Telephony.Sms.BODY)
        ctx.contentResolver.query(
            Telephony.Sms.CONTENT_URI, cols, "${Telephony.Sms.DATE} >= ?", arrayOf(sinceMs.toString()), null,
        )?.use { c ->
            while (c.moveToNext()) {
                val type = c.getInt(0)
                if (type == Telephony.Sms.MESSAGE_TYPE_DRAFT) continue
                val address = c.getString(2) ?: ""
                out.add(
                    mapOf(
                        "date" to c.getLong(1),
                        "out" to (type != Telephony.Sms.MESSAGE_TYPE_INBOX),
                        "address" to address,
                        "name" to nameFor(address),
                        "bytes" to (c.getString(3)?.toByteArray(Charsets.UTF_8)?.size ?: 0),
                        "mms" to false,
                    ),
                )
            }
        }
    }

    private fun readMms(sinceMs: Long, out: MutableList<Map<String, Any?>>) {
        val cols = arrayOf(Telephony.Mms._ID, Telephony.Mms.MESSAGE_BOX, Telephony.Mms.DATE, Telephony.Mms.MESSAGE_SIZE)
        // MMS dates are in seconds
        ctx.contentResolver.query(
            Telephony.Mms.CONTENT_URI, cols, "${Telephony.Mms.DATE} >= ?", arrayOf((sinceMs / 1000).toString()), null,
        )?.use { c ->
            while (c.moveToNext()) {
                val box = c.getInt(1)
                if (box == Telephony.Mms.MESSAGE_BOX_DRAFTS) continue
                val outgoing = box != Telephony.Mms.MESSAGE_BOX_INBOX
                val address = mmsAddress(c.getLong(0), outgoing)
                out.add(
                    mapOf(
                        "date" to c.getLong(2) * 1000,
                        "out" to outgoing,
                        "address" to address,
                        "name" to nameFor(address),
                        "bytes" to c.getInt(3),
                        "mms" to true,
                    ),
                )
            }
        }
    }

    private fun mmsAddress(id: Long, outgoing: Boolean): String {
        // PduHeaders: 137 = FROM, 151 = TO
        val type = if (outgoing) "151" else "137"
        ctx.contentResolver.query(
            Uri.parse("content://mms/$id/addr"), arrayOf("address"), "type = ?", arrayOf(type), null,
        )?.use { c -> if (c.moveToFirst()) return c.getString(0) ?: "" }
        return ""
    }

    private fun nameFor(address: String): String? {
        if (!canReadContacts || address.isEmpty()) return null
        return names.getOrPut(address) {
            try {
                ctx.contentResolver.query(
                    Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address)),
                    arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null,
                )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            } catch (_: Exception) {
                null
            }
        }
    }
}
