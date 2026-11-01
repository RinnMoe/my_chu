package moe.rinn.mychu

import moe.rinn.mychu.AppUpdateEngine.Failure

/** Target APK identity declared by the update manifest. */
data class AppUpdateTargetRequest(
    val taskId: String,
    val versionCode: Long,
    val version: String,
    val size: Long,
    val hash: String,
    val algorithm: HashAlgorithm,
)

/** Validated `merge` arguments for both update protocols. */
data class AppUpdateMergeRequest(
    val target: AppUpdateTargetRequest,
    val patchSize: Long,
    val patchHash: String,
    val patchAlgorithm: HashAlgorithm,
    val baseSha256: String?,
)

/**
 * Strict channel argument validation. Runs on the native side so a changed or
 * compromised Dart layer cannot skip size, digest or identity checks.
 */
object AppUpdateArguments {
    /** The only delta container this engine rebuilds (DiffUpdater core 2.0.0). */
    const val PATCH_FORMAT = "hdiffpatch-zlib"

    /** Android's own `versionCode` ceiling; a byte-size cap does not apply to it. */
    const val MAX_VERSION_CODE = 2_100_000_000L

    private const val MAX_TEXT = 256

    fun merge(args: Map<*, *>): AppUpdateMergeRequest {
        requirePatchFormat(args)
        val target = target(args)
        val algorithm = HashAlgorithm.parse(args["patchHashAlgorithm"])
        return AppUpdateMergeRequest(
            target = target,
            patchSize = number(args, "patchSize"),
            patchHash = AppUpdateVerifier.parseHash(args["patchHash"], algorithm),
            patchAlgorithm = algorithm,
            baseSha256 = optionalHash(args, "baseSha256"),
        )
    }

    fun verifyFull(args: Map<*, *>): AppUpdateTargetRequest = target(args)

    fun text(args: Map<*, *>, key: String): String {
        val value = args[key] as? String ?: throw Failure("INVALID_UPDATE_ARGUMENT")
        if (value.isEmpty() || value.length > MAX_TEXT) throw Failure("INVALID_UPDATE_ARGUMENT")
        return value
    }

    fun number(args: Map<*, *>, key: String, max: Long = AppUpdateVerifier.MAX_BYTES): Long {
        val value = (args[key] as? Number)?.toLong() ?: throw Failure("INVALID_UPDATE_ARGUMENT")
        if (value < 1 || value > max) throw Failure("INVALID_UPDATE_ARGUMENT")
        return value
    }

    private fun target(args: Map<*, *>): AppUpdateTargetRequest {
        val algorithm = HashAlgorithm.parse(args["targetHashAlgorithm"])
        return AppUpdateTargetRequest(
            taskId = text(args, "taskId"),
            versionCode = number(args, "versionCode", MAX_VERSION_CODE),
            version = text(args, "version"),
            size = number(args, "targetSize"),
            hash = AppUpdateVerifier.parseHash(args["targetHash"], algorithm),
            algorithm = algorithm,
        )
    }

    /** Upstream base digest is always SHA-256; absence means no upstream hash exists. */
    private fun optionalHash(args: Map<*, *>, key: String): String? {
        val raw = args[key] ?: return null
        return AppUpdateVerifier.parseHash(raw, HashAlgorithm.SHA256)
    }

    private fun requirePatchFormat(args: Map<*, *>) {
        val format = args["patchFormat"] as? String ?: throw Failure("INVALID_UPDATE_ARGUMENT")
        if (format != PATCH_FORMAT) throw Failure("PATCH_FORMAT_UNSUPPORTED")
    }
}
