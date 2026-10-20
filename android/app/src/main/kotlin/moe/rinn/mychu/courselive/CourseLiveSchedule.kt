package moe.rinn.mychu.courselive

import org.json.JSONObject

/**
 * One course block inside the persisted plan.
 *
 * Display eligibility is derived from real time, never stored, so a delayed or
 * missed broadcast can always recover by recomputing from the current clock.
 */
data class CourseLiveBlock(
    val eventId: String,
    val name: String,
    val location: String,
    val startAt: Long,
    val endAt: Long,
    val windowStart: Long,
) {
    fun phaseAt(now: Long): CourseLivePhase = when {
        now < windowStart -> CourseLivePhase.IDLE
        now < startAt -> CourseLivePhase.PRE
        now < endAt -> CourseLivePhase.ONGOING
        else -> CourseLivePhase.ENDED
    }

    companion object {
        /** Returns null for any block that cannot be displayed safely. */
        fun parse(raw: JSONObject?): CourseLiveBlock? {
            raw ?: return null
            val eventId = raw.optString("eventId").trim()
            val name = raw.optString("name").trim()
            if (eventId.isEmpty() || name.isEmpty()) return null
            val startAt = raw.optLong("startAt", -1)
            val endAt = raw.optLong("endAt", -1)
            val windowStart = raw.optLong("windowStart", startAt)
            val windowEnd = raw.optLong("windowEnd", startAt)
            if (startAt <= 0 || endAt <= startAt) return null
            if (windowStart > startAt) return null
            // Accept both pre-only and whole-course v1 windows; execution uses
            // the authoritative start/end fields without changing ownership.
            if (windowEnd < startAt || (windowEnd != startAt && windowEnd < endAt)) return null
            return CourseLiveBlock(
                eventId = eventId,
                name = name,
                location = raw.optString("location").trim(),
                startAt = startAt,
                endAt = endAt,
                windowStart = windowStart,
            )
        }
    }
}

enum class CourseLivePhase { IDLE, PRE, ONGOING, ENDED }

/**
 * Pure scheduling arithmetic: when must the device wake up, and which block is
 * real right now.
 */
object CourseLiveSchedule {
    /** Exact stage boundaries; progress checkpoints use a separate slot. */
    fun nextChangeAt(block: CourseLiveBlock, now: Long): Long? = when (block.phaseAt(now)) {
        CourseLivePhase.IDLE -> block.windowStart
        CourseLivePhase.PRE -> block.startAt
        CourseLivePhase.ONGOING -> block.endAt
        CourseLivePhase.ENDED -> null
    }

    fun selectBlock(
        blocks: List<CourseLiveBlock>,
        now: Long,
        dismissed: (CourseLiveBlock) -> Boolean,
    ): CourseLiveBlock? = blocks
        .filter { it.phaseAt(now) in setOf(CourseLivePhase.PRE, CourseLivePhase.ONGOING) && !dismissed(it) }
        .minWithOrNull(compareBy({ if (it.phaseAt(now) == CourseLivePhase.ONGOING) 0 else 1 },
            { it.startAt }, { it.endAt }, { it.eventId }))
}

/**
 * Persisted plan plus the account-generation fence. [CourseLiveStore] keeps the
 * plan minimal: no account, no credential, no full timetable.
 */
data class CourseLivePlan(
    val owner: String,
    val generation: Long,
    val blocks: List<CourseLiveBlock>,
) {
    companion object {
        const val VERSION = 1

        /**
         * A plan is accepted only when every course is usable. Dropping a
         * malformed course would silently revoke or move an activity, so an
         * unusable payload keeps whatever plan the device already has.
         */
        fun fromRaw(raw: JSONObject?): CourseLivePlan? {
            raw ?: return null
            if (raw.optInt("version", 0) != VERSION) return null
            if (!PlanCodec.isOwner(raw.optString("owner"))) return null
            val generation = raw.optLong("generation", -1)
            if (generation < 0) return null
            val array = raw.optJSONArray("courses") ?: return null
            if (array.length() == 0) return null
            val blocks = ArrayList<CourseLiveBlock>(array.length())
            for (index in 0 until array.length()) {
                val block = CourseLiveBlock.parse(array.optJSONObject(index)) ?: return null
                blocks.add(block)
            }
            return CourseLivePlan(
                owner = raw.optString("owner"),
                generation = generation,
                blocks = blocks.distinctBy { it.eventId },
            )
        }
    }
}

object PlanCodec {
    private val OWNER = Regex("[a-f0-9]{48}")

    fun isOwner(value: String?): Boolean = value != null && OWNER.matches(value)
}
