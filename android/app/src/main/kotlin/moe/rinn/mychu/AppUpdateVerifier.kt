package moe.rinn.mychu

import java.io.File
import java.security.MessageDigest

/** Hash algorithm published by an update protocol for one file. */
enum class HashAlgorithm(val jcaName: String, val hexLength: Int) {
    SHA256("SHA-256", 64),
    MD5("MD5", 32);

    companion object {
        /** Strict parser for the channel tokens; anything else is an invalid argument. */
        fun parse(raw: Any?): HashAlgorithm = when (raw) {
            "sha256" -> SHA256
            "md5" -> MD5
            else -> throw AppUpdateEngine.Failure("INVALID_UPDATE_ARGUMENT")
        }
    }
}

/**
 * Framework-free update checks shared by both update protocols: Fenfa deltas
 * publish SHA-256 while UpgradeLink publishes MD5 only. Kept independent of
 * Context/PackageManager so the rules stay unit testable on the JVM.
 */
object AppUpdateVerifier {
    /** Headroom beyond the rebuilt APK for the installer's own copies. */
    const val STORAGE_MARGIN_BYTES = 32L * 1024 * 1024

    /** Upper bound for every size/count argument accepted from the channel. */
    const val MAX_BYTES = 1024L * 1024 * 1024

    /** Lowercase hex digest of a file, computed with the given algorithm. */
    fun digest(file: File, algorithm: HashAlgorithm): String {
        val digest = MessageDigest.getInstance(algorithm.jcaName)
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

    /** Strictly parses an expected digest: exact algorithm length, hex only, lowercased. */
    fun parseHash(raw: Any?, algorithm: HashAlgorithm): String {
        val value = raw as? String ?: throw AppUpdateEngine.Failure("INVALID_UPDATE_ARGUMENT")
        if (value.length != algorithm.hexLength) throw AppUpdateEngine.Failure("INVALID_UPDATE_ARGUMENT")
        if (!value.all { it.isHexDigit() }) throw AppUpdateEngine.Failure("INVALID_UPDATE_ARGUMENT")
        return value.lowercase()
    }

    /**
     * Verifies one downloaded or rebuilt file against its declared size and digest.
     * [mismatchCode] keeps patch and target failures distinct for the caller.
     */
    fun verifyFile(
        file: File,
        expectedSize: Long,
        expectedHash: String,
        algorithm: HashAlgorithm,
        mismatchCode: String,
    ) {
        if (!file.isFile || file.length() != expectedSize) throw AppUpdateEngine.Failure(mismatchCode)
        if (digest(file, algorithm) != expectedHash.lowercase()) throw AppUpdateEngine.Failure(mismatchCode)
    }

    /** Rejects a task whose free space cannot hold the rebuilt APK plus the margin. */
    fun checkStorage(availableBytes: Long, targetSize: Long, marginBytes: Long = STORAGE_MARGIN_BYTES) {
        if (availableBytes < targetSize + marginBytes) throw AppUpdateEngine.Failure("UPDATE_STORAGE")
    }

    /** A usable installed source APK: a readable, non-empty regular file. */
    fun readableSource(file: File): Boolean = file.isFile && file.canRead() && file.length() > 0

    /** Lowercase hex encoding shared with [AppUpdateEngine]. */
    internal fun ByteArray.hex() = joinToString("") { "%02x".format(it) }

    private fun Char.isHexDigit() = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
}
