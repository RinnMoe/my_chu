package moe.rinn.mychu

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/** Account-fenced local scheduler. All entrypoints run under the same lock. */
object TimeReminderEngine {
    private const val STORE = "mychu_time_reminders_v2"
    private const val ACTION = "moe.rinn.mychu.TIME_REMINDER"
    private const val HORIZON = 14L * 24 * 60 * 60 * 1000
    private val targets = mapOf("course" to "feature.academic.schedule",
        "exam" to "feature.academic.exams", "deadline" to "feature.portal.personal")
    private fun prefs(c: Context) = c.getSharedPreferences(STORE, Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(NotificationManager::class.java)
    private fun alarms(c: Context) = c.getSystemService(AlarmManager::class.java)
    private fun read(c: Context): List<JSONObject> {
        val array = runCatching { JSONArray(prefs(c).getString("events", "[]")) }.getOrElse { JSONArray() }
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }
    private fun write(c: Context, events: List<JSONObject>) {
        check(prefs(c).edit().putString("events", JSONArray(events).toString()).commit())
    }
    fun exact(c: Context) = Build.VERSION.SDK_INT < 31 || alarms(c).canScheduleExactAlarms()
    fun notifications(c: Context) = manager(c).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    private fun matches(c: Context, owner: String, generation: Long) = owner.isNotEmpty() &&
        prefs(c).getString("owner", "") == owner && prefs(c).getLong("generation", 0) == generation
    private fun key(c: Context, e: JSONObject) = Uri.Builder().scheme("mychu-reminder")
        .authority(prefs(c).getString("owner", "")).appendPath(e.getString("category"))
        .appendPath(e.getString("eventId")).build().toString()
    private fun pending(c: Context, e: JSONObject): PendingIntent {
        val intent = Intent(c, TimeReminderReceiver::class.java).setAction(ACTION)
            .setData(Uri.parse(key(c, e))).putExtra("owner", prefs(c).getString("owner", ""))
            .putExtra("eventId", e.getString("eventId")).putExtra("category", e.getString("category"))
            .putExtra("triggerAt", e.getLong("triggerAt"))
        return PendingIntent.getBroadcast(c, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun cancel(c: Context, e: JSONObject, delivered: Boolean = false) {
        val p = pending(c, e); alarms(c).cancel(p); p.cancel()
        if (delivered) manager(c).cancel(key(c, e), 1)
    }
    @Synchronized fun deactivate(c: Context) {
        val generation = prefs(c).getLong("generation", 0) + 1
        read(c).forEach { cancel(c, it, true) }
        val cleaned = prefs(c).getBoolean("legacy_reset", false)
        check(prefs(c).edit().clear().putLong("generation", generation).putBoolean("legacy_reset", cleaned).commit())
    }
    @Synchronized private fun activate(c: Context, owner: String): Long {
        require(owner.matches(Regex("[a-f0-9]{48}")))
        if (prefs(c).getString("owner", "") != owner) deactivate(c)
        val generation = prefs(c).getLong("generation", 0) + 1
        check(prefs(c).edit().putString("owner", owner).putLong("generation", generation).commit())
        reschedule(c)
        return generation
    }
    @Synchronized private fun replace(c: Context, owner: String, generation: Long,
        category: String, input: List<JSONObject>, active: List<String>, covered: List<Long>?) {
        if (!matches(c, owner, generation)) return
        require(targets.containsKey(category))
        if (category == "course") { cancelCategory(c, owner, generation, category); return }
        val now = System.currentTimeMillis()
        val old = read(c)
        val ledger = JSONObject(prefs(c).getString("ledger", "{}"))
        ledger.keys().asSequence().toList().filter { ledger.optLong(it) <= now }.forEach { ledger.remove(it) }
        check(prefs(c).edit().putString("ledger", ledger.toString()).commit())
        val valid = input.filter { e ->
            e.optString("category") == category && e.optString("eventId").isNotBlank() &&
                e.optString("title").isNotBlank() && e.optString("targetAppId") == targets[category] &&
                e.optLong("triggerAt") > now && e.optLong("triggerAt") <= now + HORIZON &&
                e.optLong("validUntil") >= e.optLong("triggerAt")
        }.distinctBy { it.getString("eventId") }.map { e ->
            val previous = old.firstOrNull { it.optString("category") == category && it.optString("eventId") == e.optString("eventId") }
            e.put("delivered", previous?.optBoolean("delivered") == true || ledger.has(key(c, e)))
        }
        fun inScope(e: JSONObject): Boolean = covered == null || covered.any {
            e.optLong("validUntil") >= it && e.optLong("validUntil") < it + 86400000L
        }
        val outside = old.filter { it.optString("category") == category && !inScope(it) }
        val identities = active.toSet()
        // Delivered occurrences stay indexed for cancellation and deduplication.
        val keptDelivered = old.filter { it.optString("category") == category && it.optBoolean("delivered") &&
            it.optString("eventId") in identities && it.optLong("validUntil") > now }
        val retained = (valid + keptDelivered + outside).distinctBy { it.getString("eventId") }
        old.filter { it.optString("category") == category }.forEach { e ->
            cancel(c, e, retained.none { it.optString("eventId") == e.optString("eventId") })
        }
        write(c, old.filter { it.optString("category") != category } + retained)
        reschedule(c)
    }
    @Synchronized private fun cancelCategory(c: Context, owner: String, generation: Long, category: String) {
        if (!matches(c, owner, generation)) return
        val old = read(c)
        old.filter { it.optString("category") == category }.forEach { cancel(c, it, true) }
        write(c, old.filter { it.optString("category") != category })
        reschedule(c)
    }
    /** Upgrade cleanup is independent from the ordinary reminder account or enabled flags. */
    private fun retireNormalCourses(c: Context): List<JSONObject> {
        val stored = read(c)
        val retired = stored.filter { it.optString("category") == "course" }
        retired.forEach { cancel(c, it, true) }
        if (Build.VERSION.SDK_INT >= 26) {
            manager(c).activeNotifications.filter { it.notification.channelId == "mychu_time_course" }
                .forEach { manager(c).cancel(it.tag, it.id) }
        }
        val retained = stored.filter { it.optString("category") != "course" }
        if (retired.isNotEmpty()) write(c, retained)
        return retained
    }

    @Synchronized fun reschedule(c: Context) {
        val now = System.currentTimeMillis()
        val all = retireNormalCourses(c)
        all.filter { it.optLong("validUntil") <= now || it.optLong("triggerAt") > now }
            .forEach { cancel(c, it, it.optLong("validUntil") <= now) }
        // Keep due identities until expiry: another same-time broadcast may already be queued.
        val live = all.filter { it.optLong("validUntil") > now }
        write(c, live)
        if (prefs(c).getString("owner", "").isNullOrBlank() || !exact(c) || !notifications(c)) return
        live.filter { !it.optBoolean("delivered") && it.optLong("triggerAt") > now }.sortedBy { it.getLong("triggerAt") }.take(64).forEach {
            try { alarms(c).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it.getLong("triggerAt"), pending(c, it)) }
            catch (_: SecurityException) { return }
        }
    }
    @Synchronized fun deliver(c: Context, intent: Intent) {
        if (intent.getStringExtra("category") == "course") { reschedule(c); return }
        if (intent.action != ACTION || intent.getStringExtra("owner") != prefs(c).getString("owner", "")) return
        val all = read(c)
        val e = all.firstOrNull { key(c, it) == intent.dataString &&
            it.optLong("triggerAt") == intent.getLongExtra("triggerAt", -1) } ?: return
        val now = System.currentTimeMillis()
        if (e.optBoolean("delivered") || e.getLong("triggerAt") > now || e.getLong("validUntil") <= now) return
        if (!exact(c) || !notifications(c)) { reschedule(c); return }
        val category = e.getString("category")
        val channel = "mychu_time_$category"
        val title = mapOf("course" to "课前提醒", "exam" to "考试提醒", "deadline" to "待办截止提醒")[category] ?: return
        if (Build.VERSION.SDK_INT >= 26) manager(c).createNotificationChannel(NotificationChannel(channel, title, NotificationManager.IMPORTANCE_DEFAULT).apply {
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        })
        if (Build.VERSION.SDK_INT >= 26 && manager(c).getNotificationChannel(channel)?.importance == NotificationManager.IMPORTANCE_NONE) return
        val launch = Intent(c, MainActivity::class.java).setAction(MainActivity.ACTION_OPEN_APP)
            .setData(Uri.parse(key(c, e))).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_TARGET_APP_ID, targets[category])
            .putExtra("reminderOwner", prefs(c).getString("owner", ""))
            .putExtra("reminderCategory", category).putExtra("reminderEvent", e.getString("eventId"))
            .putExtra("reminderUntil", e.getLong("validUntil"))
        val content = PendingIntent.getActivity(c, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        // Persist before posting: at most once even if the process dies here.
        val ledger = JSONObject(prefs(c).getString("ledger", "{}"))
        ledger.put(key(c, e), e.getLong("validUntil"))
        check(prefs(c).edit().putString("ledger", ledger.toString()).commit())
        e.put("delivered", true); write(c, all)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel)
            else { @Suppress("DEPRECATION") Notification.Builder(c) }
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(e.getLong("validUntil") - now)
        manager(c).notify(key(c, e), 1, builder
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle(e.getString("title"))
            .setContentText(e.optString("body")).setStyle(Notification.BigTextStyle().bigText(e.optString("body")))
            .setCategory(Notification.CATEGORY_REMINDER).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true).setContentIntent(content).build())
        reschedule(c)
    }
    @Synchronized private fun validate(c: Context, args: Map<*, *>): Boolean {
        if (args["category"] == "course") return false
        if (args["owner"] != prefs(c).getString("owner", "")) return false
        return read(c).any { it.optString("category") == args["category"] &&
            it.optString("eventId") == args["eventId"] && it.optLong("validUntil") > System.currentTimeMillis() &&
            targets[it.optString("category")] == args["targetAppId"] }
    }
    @Synchronized fun resetLegacy(c: Context) {
        retireNormalCourses(c)
        refreshNotificationIcons(c)
        val p = prefs(c)
        if (p.getBoolean("legacy_reset", false)) return
        RetiredLiveNotificationCleanup.run(c)
        val old = c.getSharedPreferences("mychu_scheduled_alerts", Context.MODE_PRIVATE)
        for ((name, raw) in old.all) {
            if (!name.startsWith("schedule.") || raw !is String) continue
            val array = runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
            for (i in 0 until array.length()) {
                val e = array.optJSONObject(i) ?: continue
                val legacyKey = "${e.optString("providerId")}|${e.optString("eventId")}|${e.optLong("triggerAt")}"
                val intent = Intent("moe.rinn.mychu.action.SCHEDULED_ALERT_DELIVER").setComponent(
                    ComponentName(c.packageName, "moe.rinn.mychu.ScheduledAlertReceiver"))
                PendingIntent.getBroadcast(c, legacyKey.hashCode(), intent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)?.let { alarms(c).cancel(it); it.cancel() }
                manager(c).cancel(legacyKey.hashCode())
            }
        }
        val retired = setOf("mychu_scheduled_reminders", "in_app_changes")
        if (Build.VERSION.SDK_INT >= 26) manager(c).activeNotifications.filter { it.notification.channelId in retired }.forEach {
            manager(c).cancel(it.tag, it.id)
        }
        if (Build.VERSION.SDK_INT < 26) manager(c).activeNotifications.filter {
            it.tag == null && it.notification.category == Notification.CATEGORY_REMINDER
        }.forEach { manager(c).cancel(it.id) }
        if (Build.VERSION.SDK_INT >= 26) retired.forEach { manager(c).deleteNotificationChannel(it) }
        check(old.edit().clear().commit())
        check(p.edit().putBoolean("legacy_reset", true).commit())
    }
    private fun refreshNotificationIcons(c: Context) {
        if (Build.VERSION.SDK_INT < 24 || !notifications(c)) return
        val notificationManager = manager(c)
        val activePrefix = Uri.Builder().scheme("mychu-reminder")
            .authority(prefs(c).getString("owner", "")).build().toString() + "/"
        for (posted in notificationManager.activeNotifications) {
            // Only refresh this scheduler's current-account reminders.
            if (posted.id != 1 || posted.tag?.startsWith(activePrefix) != true) continue
            val notification = posted.notification
            val icon = notification.smallIcon
            if (icon != null && runCatching {
                icon.resPackage == c.packageName && icon.resId == R.mipmap.ic_launcher
            }.getOrDefault(false)) continue
            val builder = Notification.Builder.recoverBuilder(c, notification)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOnlyAlertOnce(true)
            if (Build.VERSION.SDK_INT >= 26 && notification.timeoutAfter > 0) {
                val remaining = posted.postTime + notification.timeoutAfter - System.currentTimeMillis()
                if (remaining <= 0) {
                    notificationManager.cancel(posted.tag, posted.id)
                    continue
                }
                builder.setTimeoutAfter(remaining)
            }
            notificationManager.notify(posted.tag, posted.id, builder.build())
        }
    }
    fun register(context: Context, engine: FlutterEngine) {
        val c = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "mychu/time_reminders").setMethodCallHandler { call, result ->
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                when (call.method) {
                    "status" -> result.success(mapOf("notifications" to notifications(c), "exact" to exact(c)))
                    "resetLegacy" -> { resetLegacy(c); result.success(null) }
                    "activate" -> result.success(activate(c, args["owner"] as String))
                    "deactivate" -> { deactivate(c); result.success(null) }
                    "replaceCategory" -> {
                        val events = (args["events"] as List<*>).map { JSONObject(it as Map<*, *>) }
                        replace(c, args["owner"] as String, (args["generation"] as Number).toLong(), args["category"] as String, events, (args["activeEvents"] as List<*>).filterIsInstance<String>(),
                            (args["coveredDays"] as? List<*>)?.filterIsInstance<Number>()?.map { it.toLong() })
                        result.success(null)
                    }
                    "cancelCategory" -> { cancelCategory(c, args["owner"] as String,
                        (args["generation"] as Number).toLong(), args["category"] as String); result.success(null) }
                    "validateLaunch" -> result.success(validate(c, args))
                    "reschedule" -> { reschedule(c); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("REMINDER_FAILED", "时间提醒操作失败", null) }
        }
    }
}

class TimeReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TimeReminderEngine.deliver(context, intent)
    }
}
