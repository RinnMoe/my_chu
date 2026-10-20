package moe.rinn.mychu.courselive

import android.content.Context
import moe.rinn.mychu.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Local Debug fixture. The original native session is durably saved before replacement. */
object CourseLiveDeveloperTest {
    private const val BACKUP = "mychu_course_live_developer_backup"

    fun start(context: Context, delayed: Boolean): Map<String, Any> {
        check(BuildConfig.DEBUG)
        stop(context)
        val store = context.getSharedPreferences(CourseLiveStore.STORE, Context.MODE_PRIVATE)
        val snapshot = JSONObject(store.all)
        check(context.getSharedPreferences(BACKUP, Context.MODE_PRIVATE).edit()
            .putString("snapshot", snapshot.toString()).commit())
        try {
            val owner = "dddddddddddddddddddddddddddddddddddddddddddddddd"
            val generation = CourseLiveEngine.activate(context, owner)
            val now = System.currentTimeMillis()
            val opens = if (delayed) now + 60_000 else now - 1_000
            val starts = if (delayed) now + 180_000 else now + 120_000
            val course = JSONObject().put("eventId", "dev-" + UUID.randomUUID())
                .put("name", "虚拟课程 · 高等数学").put("location", "测试教室 A101")
                .put("startAt", starts).put("endAt", starts + 120_000)
                .put("windowStart", opens).put("windowEnd", starts)
            val payload = JSONObject().put("version", 1).put("owner", owner)
                .put("generation", generation).put("courses", JSONArray().put(course))
            CourseLiveEngine.replacePlan(context, owner, generation, payload)
            return mapOf("windowStart" to opens, "startAt" to starts)
        } catch (error: Exception) {
            stop(context)
            throw error
        }
    }

    /** Also called before real account mutations and when Flutter reconnects. */
    fun stop(context: Context, reschedule: Boolean = true) {
        check(BuildConfig.DEBUG)
        val backup = context.getSharedPreferences(BACKUP, Context.MODE_PRIVATE)
        val raw = backup.getString("snapshot", null) ?: return
        val snapshot = JSONObject(raw)
        CourseLiveEngine.deactivate(context)
        val store = context.getSharedPreferences(CourseLiveStore.STORE, Context.MODE_PRIVATE)
        val editor = store.edit().clear()
        snapshot.keys().forEach { key ->
            when (val value = snapshot.get(key)) {
                is String -> editor.putString(key, value)
                is Number -> editor.putLong(key, value.toLong())
                else -> error("Unexpected course activity preference type")
            }
        }
        check(editor.commit())
        if (reschedule) CourseLiveEngine.reschedule(context)
        check(backup.edit().clear().commit())
    }
}
