package moe.rinn.mychu

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.UUID

/**
 * Owns the private per-task update directories under `cacheDir/app_updates`.
 * Plain java.io so retention, duplicate-task and cleanup rules stay unit
 * testable; the engine serializes access with its own lock.
 */
class AppUpdateWorkspace(
    val root: File,
    private val now: () -> Long = System::currentTimeMillis,
    private val sessions: MutableMap<String, Session> = mutableMapOf(),
) {
    companion object {
        /** Outputs may still be open by the system installer. Keep for 24 hours. */
        const val RETENTION_MS = 24L * 60 * 60 * 1000
        const val PATCH_NAME = "update.hdiff"
        const val FULL_NAME = "full.apk"
        const val OUTPUT_NAME = "target.apk"
    }

    /** One live task workspace. Never retains a Context, Activity or Flutter result. */
    class Session(
        val taskId: String,
        val directory: File,
        val source: File,
        val sourceHash: String,
    ) {
        val patch: File get() = File(directory, PATCH_NAME)
        val full: File get() = File(directory, FULL_NAME)
        val output: File get() = File(directory, OUTPUT_NAME)
    }

    /** Creates the root, expires stale workspaces and rejects a second live task. */
    fun prepare() {
        root.mkdirs()
        cleanup()
        if (sessions.isNotEmpty()) throw AppUpdateEngine.Failure("UPDATE_BUSY")
    }

    /** Deletes only our own expired UUID-named child directories; never follows links. */
    fun cleanup() {
        if (canonical(root) == null) return
        val live = sessions.values.mapNotNull { canonical(it.directory) }.toSet()
        val timestamp = now()
        for (child in root.listFiles().orEmpty()) {
            if (!child.isDirectory || isSymbolicLink(child) || !isTaskDirectory(child.name)) continue
            val path = canonical(child) ?: continue
            if (path in live) continue
            if (timestamp - child.lastModified() > RETENTION_MS) child.deleteRecursively()
        }
    }

    /** Registers a new task workspace under a fresh task id. */
    fun begin(source: File, sourceHash: String): Session {
        val taskId = UUID.randomUUID().toString()
        val directory = File(root, taskId)
        if (!directory.mkdirs()) throw AppUpdateEngine.Failure("UPDATE_STORAGE")
        return Session(taskId, directory, source, sourceHash).also { sessions[taskId] = it }
    }

    fun session(taskId: String): Session =
        sessions[taskId] ?: throw AppUpdateEngine.Failure("INVALID_UPDATE_TASK")

    /** Releases a task. Unknown task ids are a no-op so dispose-time cleanup stays safe. */
    fun finish(taskId: String, retainApk: Boolean) {
        val session = sessions.remove(taskId) ?: return
        if (retainApk) {
            session.directory.listFiles()?.filter { it.name != OUTPUT_NAME }?.forEach { it.delete() }
            session.directory.setLastModified(now())
        } else {
            session.directory.deleteRecursively()
        }
    }

    /** Usable space of the update root, falling back to its parent before it exists. */
    fun availableBytes(): Long {
        val directory = root.takeIf { it.isDirectory } ?: root.parentFile ?: return 0L
        return directory.usableSpace
    }

    private fun canonical(file: File?): String? = try {
        file?.canonicalPath
    } catch (error: IOException) {
        null
    }

    private fun isSymbolicLink(file: File): Boolean = try {
        Files.isSymbolicLink(file.toPath())
    } catch (error: IOException) {
        true
    }

    private fun isTaskDirectory(name: String): Boolean {
        val parsed = try {
            UUID.fromString(name)
        } catch (error: IllegalArgumentException) {
            return false
        }
        return parsed.toString() == name
    }
}
