package moe.rinn.mychu.courselive

import android.content.Context
import org.json.JSONObject

/**
 * Minimal native persistence for the course activity.
 *
 * The store never holds an account, a credential or the full timetable. It
 * owns one plan per owner binding plus a small de-duplication ledger for
 * dismissed occurrences, and keeps a monotonic generation so a stale broadcast
 * from a previous account can never republish anything.
 */
class CourseLiveStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences(STORE, Context.MODE_PRIVATE)

    data class Bound(
        val owner: String,
        val generation: Long,
    )

    fun bound(): Bound? {
        val owner = prefs.getString(KEY_OWNER, null) ?: return null
        if (!PlanCodec.isOwner(owner)) return null
        return Bound(owner, prefs.getLong(KEY_GENERATION, 0))
    }

    fun matches(owner: String?, generation: Long): Boolean =
        owner != null && owner == prefs.getString(KEY_OWNER, null) &&
            generation == prefs.getLong(KEY_GENERATION, 0)

    /** Rebinding to a different owner clears every previous record. */
    fun activate(owner: String): Long {
        require(PlanCodec.isOwner(owner)) { "invalid owner" }
        val previous = prefs.getString(KEY_OWNER, null)
        val generation = prefs.getLong(KEY_GENERATION, 0) + 1
        val editor = prefs.edit()
            .putString(KEY_OWNER, owner)
            .putLong(KEY_GENERATION, generation)
        if (previous != owner) {
            editor.remove(KEY_PLAN)
            editor.remove(KEY_LEDGER)
        }
        check(editor.commit()) { "course live activity store write failed" }
        return generation
    }

    /** Invalidates the current generation, then drops plan, ledger and posted state. */
    fun deactivate() {
        val generation = prefs.getLong(KEY_GENERATION, 0) + 1
        check(
            prefs.edit()
                .clear()
                .putLong(KEY_GENERATION, generation)
                .commit(),
        ) { "course live activity store write failed" }
    }

    fun writePlan(raw: JSONObject) {
        check(prefs.edit().putString(KEY_PLAN, raw.toString()).commit()) {
            "course live activity plan write failed"
        }
    }

    fun clearPlan() {
        check(prefs.edit().remove(KEY_PLAN).commit()) {
            "course live activity plan write failed"
        }
    }

    fun readPlan(): CourseLivePlan? {
        val raw = prefs.getString(KEY_PLAN, null) ?: return null
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        return CourseLivePlan.fromRaw(json)
    }

    /** The plan exactly as it was stored, for handing back to the shared layer. */
    fun rawPlan(): String? = prefs.getString(KEY_PLAN, null)

    /** Ledger entries expire with the occurrence they de-duplicate. */
    fun ledger(): Map<String, Long> {
        val raw = prefs.getString(KEY_LEDGER, null) ?: return emptyMap()
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
        return json.keys().asSequence().associateWith { json.optLong(it, 0L) }
    }

    fun dismiss(eventId: String, until: Long) {
        require(eventId.isNotBlank()) { "invalid dismissal" }
        val json = JSONObject()
        ledger().forEach { (key, value) -> json.put(key, value) }
        json.put(eventId, until)
        check(prefs.edit().putString(KEY_LEDGER, json.toString()).commit()) {
            "course live activity ledger write failed"
        }
    }

    fun pruneLedger(now: Long) {
        val json = JSONObject()
        ledger().forEach { (key, until) ->
            if (until > now) json.put(key, until)
        }
        check(prefs.edit().putString(KEY_LEDGER, json.toString()).commit()) {
            "course live activity ledger write failed"
        }
    }

    /** Last displayed occurrence and its channel, for diagnostics only. */
    fun rememberedDisplay(): Pair<String, Long>? {
        val eventId = prefs.getString(KEY_DISPLAYED, null) ?: return null
        if (eventId.isBlank()) return null
        return eventId to prefs.getLong(KEY_DISPLAYED_AT, 0)
    }

    fun rememberDisplay(eventId: String, at: Long) {
        check(
            prefs.edit()
                .putString(KEY_DISPLAYED, eventId)
                .putLong(KEY_DISPLAYED_AT, at)
                .commit(),
        ) { "course live activity store write failed" }
    }

    fun forgetDisplay() {
        check(prefs.edit().remove(KEY_DISPLAYED).remove(KEY_DISPLAYED_AT).commit()) {
            "course live activity store write failed"
        }
    }

    companion object {
        const val STORE = "mychu_course_live_activity_v1"
        const val KEY_OWNER = "owner"
        const val KEY_GENERATION = "generation"
        const val KEY_PLAN = "plan"
        const val KEY_LEDGER = "dismissed"
        const val KEY_DISPLAYED = "displayed_event"
        const val KEY_DISPLAYED_AT = "displayed_at"
    }
}
