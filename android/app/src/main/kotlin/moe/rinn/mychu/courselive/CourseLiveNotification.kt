package moe.rinn.mychu.courselive

/** One render handed to a platform channel. */
data class CourseLiveNotification(
    val owner: String,
    val generation: Long,
    val eventId: String,
    val name: String,
    val location: String,
    /** Absolute instant the course starts; displayed as fixed local-campus time. */
    val startAt: Long,
    val phase: CourseLivePhase,
    val progress: Int?,
    /** Non-negative millisecond timeout; expired content never lingers. */
    val timeoutMillis: Long,
)
