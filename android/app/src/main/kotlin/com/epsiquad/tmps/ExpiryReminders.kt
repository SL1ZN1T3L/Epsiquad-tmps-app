package com.epsiquad.tmps

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject

/**
 * Напоминания о скором окончании срока хранилища.
 *
 * Список хранилищ и «за сколько напомнить» приходят из Dart и сохраняются
 * в SharedPreferences: по ним будильники ставятся заново после перезагрузки
 * телефона. Используется неточный будильник (setAndAllowWhileIdle), которому
 * не нужно отдельное разрешение; срабатывает он с небольшой погрешностью.
 */
object ExpiryReminders {
    private const val PREFS = "tmps_expiry"
    private const val KEY_ITEMS = "items"
    private const val KEY_LEAD = "lead_ms"
    private const val KEY_ARMED = "armed"
    private const val KEY_NOTIFIED = "notified"

    const val CHANNEL_ID = "tmps_expiry"
    const val ACTION_FIRE = "com.epsiquad.tmps.EXPIRY_REMINDER"
    const val EXTRA_CODE = "code"
    const val EXTRA_TITLE = "title"
    const val EXTRA_EXPIRES = "expiresAt"

    fun schedule(context: Context, items: JSONArray, leadMs: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_ITEMS, items.toString())
            .putLong(KEY_LEAD, leadMs)
            .apply()
        rearm(context)
    }

    fun cancelAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        disarm(context, prefs.getStringSet(KEY_ARMED, emptySet()) ?: emptySet())
        prefs.edit()
            .remove(KEY_ITEMS)
            .remove(KEY_ARMED)
            .remove(KEY_NOTIFIED)
            .apply()
    }

    /** Ставит будильники по сохранённому списку (вызывается и при загрузке системы). */
    fun rearm(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        disarm(context, prefs.getStringSet(KEY_ARMED, emptySet()) ?: emptySet())

        val lead = prefs.getLong(KEY_LEAD, 0L)
        val raw = prefs.getString(KEY_ITEMS, null)
        if (lead <= 0L || raw == null) {
            prefs.edit().remove(KEY_ARMED).apply()
            return
        }

        val items = try {
            JSONArray(raw)
        } catch (e: Exception) {
            return
        }
        val notified = prefs.getStringSet(KEY_NOTIFIED, emptySet()) ?: emptySet()
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        val armed = HashSet<String>()

        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            val code = item.optString("code")
            val expiresAt = item.optLong("expiresAt")
            if (code.isEmpty() || expiresAt <= now) continue
            if (notified.contains("$code:$expiresAt")) continue

            // Если до конца срока осталось меньше, чем «за сколько напомнить»,
            // напоминаем почти сразу, но только один раз.
            var trigger = expiresAt - lead
            if (trigger <= now) trigger = now + 5_000L

            alarms.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                trigger,
                firePendingIntent(context, code, item.optString("title"), expiresAt, create = true)!!
            )
            armed.add(code)
        }
        prefs.edit().putStringSet(KEY_ARMED, armed).apply()
    }

    private fun disarm(context: Context, codes: Set<String>) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (code in codes) {
            val pending = firePendingIntent(context, code, "", 0L, create = false) ?: continue
            alarms.cancel(pending)
            pending.cancel()
        }
    }

    private fun firePendingIntent(
        context: Context,
        code: String,
        title: String,
        expiresAt: Long,
        create: Boolean
    ): PendingIntent? {
        val intent = Intent(context, ExpiryAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            // Разные data - разные PendingIntent для каждого хранилища
            data = Uri.parse("tmps://expiry/$code")
            putExtra(EXTRA_CODE, code)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_EXPIRES, expiresAt)
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or
            (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE)
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    fun fire(context: Context, code: String, title: String, expiresAt: Long) {
        val now = System.currentTimeMillis()
        if (expiresAt <= now) return

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val notified = HashSet(prefs.getStringSet(KEY_NOTIFIED, emptySet()) ?: emptySet())
        val key = "$code:$expiresAt"
        if (!notified.add(key)) return
        prefs.edit().putStringSet(KEY_NOTIFIED, notified).apply()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Срок хранилищ", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Напоминания о скором окончании срока хранилища"
            }
        )

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        val tap = PendingIntent.getActivity(
            context,
            code.hashCode(),
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_clock)
            .setContentTitle("Хранилище «$title» скоро истечёт")
            .setContentText("Осталось ${describeLeft(expiresAt - now)}. Продлите его или заберите файлы")
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        manager.notify(code.hashCode(), notification)
    }

    private fun describeLeft(ms: Long): String {
        val hours = ms / 3_600_000L
        if (hours < 1L) return "меньше часа"
        if (hours < 48L) return "около $hours ${plural(hours, "час", "часа", "часов")}"
        val days = hours / 24L
        return "около $days ${plural(days, "день", "дня", "дней")}"
    }

    private fun plural(n: Long, one: String, few: String, many: String): String {
        val m10 = n % 10L
        val m100 = n % 100L
        return when {
            m10 == 1L && m100 != 11L -> one
            m10 in 2L..4L && (m100 < 12L || m100 > 14L) -> few
            else -> many
        }
    }
}

class ExpiryAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ExpiryReminders.ACTION_FIRE) return
        val code = intent.getStringExtra(ExpiryReminders.EXTRA_CODE) ?: return
        val title = intent.getStringExtra(ExpiryReminders.EXTRA_TITLE) ?: code
        val expiresAt = intent.getLongExtra(ExpiryReminders.EXTRA_EXPIRES, 0L)
        ExpiryReminders.fire(context, code, title, expiresAt)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> ExpiryReminders.rearm(context)
        }
    }
}
