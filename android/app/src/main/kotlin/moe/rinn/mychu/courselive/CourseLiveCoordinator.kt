package moe.rinn.mychu.courselive

/**
 * The whole native state machine, free of Android types so it can be exercised
 * directly by unit tests.
 *
 * The device layer only persists [CourseLiveSession] plus the plan, and applies
 * the [CourseLiveEffect]s this produces.
 */
data class CourseLiveSession(
    val owner: String?,
    val generation: Long,
    val blocks: List<CourseLiveBlock>,
    val dismissedUntil: Map<String, Long> = emptyMap(),
    val shownEventId: String? = null,
)

/** Everything the device layer must do after one coordination pass. */
data class CourseLiveEffect(
    /** An occurrence was dismissed in a previous pass; persisted ledger only. */
    val prunedDismissals: Boolean = false,
    /** Render this course now. */
    val post: CourseLiveNotification? = null,
    /** End the current instance before switching to a different course. */
    val endFirst: Boolean = false,
    /** Remove any rendered instance. */
    val cancelDisplay: Boolean = false,
    /** Forget the remembered occurrence (cancelled or ended). */
    val forgetDisplay: Boolean = false,
    /** Next opening, start or end transition, held on an exact alarm. */
    val nextBoundaryAt: Long? = null,
    /** A separate, non-exact progress refresh slot. */
    val nextCheckpointAt: Long? = null,
)

object CourseLiveCoordinator {
    /**
     * [canPost] false means the device cannot show anything right now; the pass
     * then only decides whether an existing instance must be removed.
     */
    fun coordinate(
        session: CourseLiveSession,
        now: Long,
        canPost: Boolean,
    ): CourseLiveEffect {
        val activeDismissals = session.dismissedUntil.filterValues { it > now }
        val pruned = activeDismissals.size != session.dismissedUntil.size
        val owner = session.owner
        if (owner == null) {
            return CourseLiveEffect(
                prunedDismissals = pruned,
                cancelDisplay = true,
                forgetDisplay = true,

            )
        }
        val dismissed = activeDismissals.keys
        if (!canPost) {
            return CourseLiveEffect(
                prunedDismissals = pruned,
                cancelDisplay = true,
                forgetDisplay = true,

            )
        }
        // Phase boundaries remain independent from non-exact progress refreshes.
        val nextBoundary = CourseLiveDisplayResolver.nextBoundaryAt(
            session.blocks,
            now,
            dismissed,
        )
        return when (val decision = CourseLiveDisplayResolver.decide(session.blocks, now, dismissed)) {
            is CourseLiveDecision.Post -> {
                val display = decision.display
                CourseLiveEffect(
                    prunedDismissals = pruned,
                    post = CourseLiveNotification(
                        owner = owner,
                        generation = session.generation,
                        eventId = display.eventId,
                        name = display.name,
                        location = display.location,
                        startAt = display.startAt,
                        phase = display.phase,
                        progress = display.progress,
                        timeoutMillis = (display.endAt - now).coerceAtLeast(1L),
                    ),
                    // Another occurrence was on screen: the single instance must
                    // be ended before the replacement is rendered.
                    endFirst = session.shownEventId != null &&
                        session.shownEventId != display.eventId,
                    cancelDisplay = false,
                    forgetDisplay = false,
                    nextBoundaryAt = nextBoundary,
                    nextCheckpointAt = if (display.phase == CourseLivePhase.ONGOING)
                        (((now / PROGRESS_GRID) + 1) * PROGRESS_GRID).takeIf { it < display.endAt }
                        else null,

                )
            }
            CourseLiveDecision.Cancel -> CourseLiveEffect(
                prunedDismissals = pruned,
                cancelDisplay = session.shownEventId != null,
                forgetDisplay = session.shownEventId != null,
                nextBoundaryAt = nextBoundary,

            )
        }
    }

    /** After a manual end the occurrence stays dismissed for this window. */
    fun dismissUntil(now: Long): Long = now + DISMISS_MILLIS

    const val PROGRESS_GRID = 5L * 60 * 1000

    const val DISMISS_MILLIS = 24L * 60 * 60 * 1000
}
