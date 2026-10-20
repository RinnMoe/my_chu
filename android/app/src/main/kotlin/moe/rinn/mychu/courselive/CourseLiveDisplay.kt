package moe.rinn.mychu.courselive

/**
 * One render of the current pre-class or ongoing course. The native layer re-derives everything from
 * real time, so a delayed broadcast never shows a stale stage.
 */
data class CourseLiveDisplay(
    val eventId: String,
    val name: String,
    val location: String,
    val startAt: Long,
    val endAt: Long,
    val phase: CourseLivePhase,
    val progress: Int?,
)

sealed interface CourseLiveDecision {
    data class Post(val display: CourseLiveDisplay) : CourseLiveDecision
    data object Cancel : CourseLiveDecision
}

/**
 * Pure display decision: which course, if any, belongs on the shade right now.
 *
 * A block only ever appears inside its own window. Once the window closes the
 * content is cancelled, so late or repeated broadcasts can neither resurrect a
 * finished course nor change what a dismissed one shows.
 */
object CourseLiveDisplayResolver {
    fun decide(
        blocks: List<CourseLiveBlock>,
        now: Long,
        dismissed: Set<String>,
    ): CourseLiveDecision {
        val displayable = CourseLiveSchedule.selectBlock(blocks, now) { it.eventId in dismissed }
            ?: return CourseLiveDecision.Cancel
        return CourseLiveDecision.Post(
            CourseLiveDisplay(
                eventId = displayable.eventId,
                name = displayable.name,
                location = displayable.location,
                startAt = displayable.startAt,
                endAt = displayable.endAt,
                phase = displayable.phaseAt(now),
                progress = if (now >= displayable.startAt)
                    (((now - displayable.startAt).toDouble() /
                        (displayable.endAt - displayable.startAt)) * 100).toInt().coerceIn(0, 100)
                    else null,
            ),
        )
    }

    /** Exact wake-up for the next opening, start or end transition. */
    fun nextBoundaryAt(
        blocks: List<CourseLiveBlock>,
        now: Long,
        dismissed: Set<String>,
    ): Long? = blocks.asSequence()
        .filter { it.eventId !in dismissed }
        .mapNotNull { CourseLiveSchedule.nextChangeAt(it, now) }
        .minOrNull()
}
