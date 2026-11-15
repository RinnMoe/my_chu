package moe.rinn.mychu

/** Pending host errors, including failures before the Flutter engine is ready. */
internal object NativeErrorLog {
    private val pending = ArrayDeque<Map<String, Any>>()
    @Volatile var onChanged: (() -> Unit)? = null

    fun record(error: Throwable, operation: String) {
        synchronized(this) {
            pending.addLast(mapOf(
                "timestamp" to System.currentTimeMillis(),
                "content" to "$operation\n[Android] ${error.stackTraceToString()}",
            ))
            while (pending.size > 300) pending.removeFirst()
        }
        onChanged?.invoke()
    }

    @Synchronized fun takeErrors(): List<Map<String, Any>> {
        val entries = pending.toList()
        pending.clear()
        return entries
    }

    @Synchronized fun clear() { pending.clear() }
}
