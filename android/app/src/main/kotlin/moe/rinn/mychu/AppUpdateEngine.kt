package moe.rinn.mychu

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.github.sisong.HPatch
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/** Private update workspaces. Never retains an Activity or a Flutter result. */
class AppUpdateEngine(context: Context) {
    private val context = context.applicationContext
    private val root = File(this.context.cacheDir, "app_updates")

    companion object {
        private val lock = Any()
        private val sessions = mutableMapOf<String, Session>()
        private const val RETENTION_MS = 24L * 60 * 60 * 1000
        private const val MAX_SIZE = 1024L * 1024 * 1024
    }

    private data class Session(val directory: File, val source: File, val sourceHash: String)
    class Failure(val code: String) : Exception(code)

    fun inspect(): Map<String, Any> = synchronized(lock) {
        root.mkdirs()
        // Outputs may still be open by the system installer. Keep for 24 hours.
        val active = sessions.values.map { it.directory.canonicalPath }.toSet()
        root.listFiles()?.filter {
            it.canonicalPath !in active && System.currentTimeMillis() - it.lastModified() > RETENTION_MS
        }?.forEach { it.deleteRecursively() }
        if (sessions.isNotEmpty()) throw Failure("UPDATE_BUSY")
        val source = File(context.applicationInfo.sourceDir)
        val hash = hash(source)
        val id = UUID.randomUUID().toString()
        val directory = File(root, id)
        if (!directory.mkdirs()) throw Failure("UPDATE_STORAGE")
        sessions[id] = Session(directory, source, hash)
        val installed = context.packageManager.getPackageInfo(context.packageName, 0)
        mapOf("taskId" to id, "directory" to directory.absolutePath,
            "packageName" to context.packageName, "versionCode" to versionCode(installed),
            "sha256" to hash, "availableBytes" to directory.usableSpace,
            "supportsDelta" to (context.applicationInfo.splitSourceDirs.isNullOrEmpty() &&
                Build.SUPPORTED_ABIS.contains("arm64-v8a")))
    }

    fun merge(args: Map<*, *>): Map<String, Any> = synchronized(lock) {
        val session = session(args)
        val patch = File(session.directory, "update.hdiff")
        val output = File(session.directory, "target.apk")
        val targetSize = number(args, "targetSize")
        if (session.directory.usableSpace < targetSize + 32L * 1024 * 1024) {
            throw Failure("UPDATE_STORAGE")
        }
        try {
            if (hash(session.source) != text(args, "fromSha256") ||
                session.sourceHash != text(args, "fromSha256")) throw Failure("BASE_MISMATCH")
            verifyBytes(patch, number(args, "patchSize"), text(args, "patchSha256"))
            // Standard HDiffPatch (zlib), pinned DiffUpdater core 2.0.0.
            if (HPatch.merge(session.source.absolutePath, patch.absolutePath, output.absolutePath) != 0) {
                throw Failure("MERGE_FAILED")
            }
            verifyTarget(output, args)
            result(output)
        } catch (error: Throwable) {
            output.delete()
            throw error
        } finally {
            patch.delete()
        }
    }

    fun verifyFull(args: Map<*, *>): Map<String, Any> = synchronized(lock) {
        val session = session(args)
        val full = File(session.directory, "full.apk")
        verifyTarget(full, args)
        val output = File(session.directory, "target.apk")
        output.delete()
        if (!full.renameTo(output)) throw Failure("UPDATE_STORAGE")
        result(output)
    }

    fun finish(args: Map<*, *>) = synchronized(lock) {
        val id = text(args, "taskId")
        val session = sessions.remove(id) ?: return@synchronized
        if (args["retainApk"] == true) {
            session.directory.listFiles()?.filter { it.name != "target.apk" }?.forEach { it.delete() }
            session.directory.setLastModified(System.currentTimeMillis())
        } else {
            session.directory.deleteRecursively()
        }
    }

    private fun session(args: Map<*, *>) = sessions[text(args, "taskId")]
        ?.takeIf { it.directory.parentFile?.canonicalFile == root.canonicalFile }
        ?: throw Failure("INVALID_UPDATE_TASK")

    private fun verifyTarget(file: File, args: Map<*, *>) {
        verifyBytes(file, number(args, "targetSize"), text(args, "targetSha256"))
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
            else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val manager = context.packageManager
        val archive = manager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: throw Failure("INVALID_TARGET_APK")
        val installed = manager.getPackageInfo(context.packageName, flags)
        if (archive.packageName != context.packageName ||
            versionCode(archive) != number(args, "versionCode") ||
            archive.versionName != text(args, "version") ||
            versionCode(archive) <= versionCode(installed)) throw Failure("TARGET_IDENTITY_MISMATCH")
        val oldSigners = signers(installed)
        if (oldSigners.isEmpty() || oldSigners != signers(archive)) throw Failure("TARGET_SIGNER_MISMATCH")
    }

    @Suppress("DEPRECATION")
    private fun signers(info: android.content.pm.PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners
            else info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).hex()
        }?.toSet().orEmpty()
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: android.content.pm.PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    private fun verifyBytes(file: File, size: Long, expected: String) {
        if (!file.isFile || file.length() != size || hash(file) != expected) throw Failure("UPDATE_HASH_MISMATCH")
    }

    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().hex()
    }

    private fun ByteArray.hex() = joinToString("") { "%02x".format(it) }
    private fun text(args: Map<*, *>, key: String) = (args[key] as? String)
        ?.takeIf { it.isNotEmpty() && it.length <= 256 } ?: throw Failure("INVALID_UPDATE_ARGUMENT")
    private fun number(args: Map<*, *>, key: String) = (args[key] as? Number)?.toLong()
        ?.takeIf { it in 1..MAX_SIZE } ?: throw Failure("INVALID_UPDATE_ARGUMENT")
    private fun result(file: File) = mapOf<String, Any>("path" to file.absolutePath, "size" to file.length())
}
