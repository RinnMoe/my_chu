package moe.rinn.mychu

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import com.github.sisong.HPatch
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import moe.rinn.mychu.AppUpdateVerifier.hex

/** Thin Android adapter over [AppUpdateWorkspace] and [AppUpdateVerifier]. */
class AppUpdateEngine(context: Context) {
    private val context = context.applicationContext
    private val workspace = AppUpdateWorkspace(
        File(this.context.cacheDir, "app_updates"),
        sessions = sessions,
    )

    companion object {
        private val lock = Any()
        private val sessions = mutableMapOf<String, AppUpdateWorkspace.Session>()
    }

    class Failure(val code: String) : Exception(code)

    /** Side-effect-free eligibility probe: never creates a task or touches storage. */
    fun capabilities(): Map<String, Any> {
        val info = context.applicationInfo
        val source = File(info.sourceDir)
        val installed = context.packageManager.getPackageInfo(context.packageName, 0)
        return mapOf(
            "packageName" to context.packageName,
            "versionCode" to versionCode(installed),
            "supportsDelta" to supportsDelta(info),
            "availableBytes" to workspace.availableBytes(),
            "sourceSize" to source.length(),
            "readable" to AppUpdateVerifier.readableSource(source),
        )
    }

    fun inspect(): Map<String, Any> = synchronized(lock) {
        workspace.prepare()
        val source = File(context.applicationInfo.sourceDir)
        val hash = AppUpdateVerifier.digest(source, HashAlgorithm.SHA256)
        val session = workspace.begin(source, hash)
        val installed = context.packageManager.getPackageInfo(context.packageName, 0)
        mapOf("taskId" to session.taskId, "directory" to session.directory.absolutePath,
            "packageName" to context.packageName, "versionCode" to versionCode(installed),
            "sha256" to hash, "availableBytes" to session.directory.usableSpace,
            "supportsDelta" to supportsDelta(context.applicationInfo))
    }

    fun merge(args: Map<*, *>): Map<String, Any> = synchronized(lock) {
        val request = AppUpdateArguments.merge(args)
        val target = request.target
        val session = workspace.session(target.taskId)
        val patch = session.patch
        val output = session.output
        AppUpdateVerifier.checkStorage(session.directory.usableSpace, target.size)
        try {
            verifyBase(session, request.baseSha256)
            AppUpdateVerifier.verifyFile(
                patch, request.patchSize, request.patchHash, request.patchAlgorithm, "PATCH_HASH_MISMATCH",
            )
            // Standard HDiffPatch (zlib), pinned DiffUpdater core 2.0.0.
            if (HPatch.merge(session.source.absolutePath, patch.absolutePath, output.absolutePath) != 0) {
                throw Failure("MERGE_FAILED")
            }
            verifyTarget(output, target)
            result(output)
        } catch (error: Throwable) {
            output.delete()
            throw error
        } finally {
            patch.delete()
        }
    }

    fun verifyFull(args: Map<*, *>): Map<String, Any> = synchronized(lock) {
        val target = AppUpdateArguments.verifyFull(args)
        val session = workspace.session(target.taskId)
        val full = session.full
        verifyTarget(full, target)
        val output = session.output
        output.delete()
        if (!full.renameTo(output)) throw Failure("UPDATE_STORAGE")
        result(output)
    }

    fun finish(args: Map<*, *>) = synchronized(lock) {
        workspace.finish(AppUpdateArguments.text(args, "taskId"), args["retainApk"] == true)
    }

    /**
     * The installed APK must still be the one seen by `inspect`; when the
     * upstream manifest also publishes a base digest it must match as well.
     */
    private fun verifyBase(session: AppUpdateWorkspace.Session, baseSha256: String?) {
        val installed = try {
            AppUpdateVerifier.digest(session.source, HashAlgorithm.SHA256)
        } catch (error: IOException) {
            throw Failure("BASE_CHANGED")
        }
        if (installed != session.sourceHash) throw Failure("BASE_CHANGED")
        if (baseSha256 != null && installed != baseSha256) throw Failure("BASE_MISMATCH")
    }

    private fun verifyTarget(file: File, target: AppUpdateTargetRequest) {
        AppUpdateVerifier.verifyFile(
            file, target.size, target.hash, target.algorithm, "TARGET_HASH_MISMATCH",
        )
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
            else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val manager = context.packageManager
        val archive = manager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: throw Failure("INVALID_TARGET_APK")
        val installed = manager.getPackageInfo(context.packageName, flags)
        if (archive.packageName != context.packageName ||
            versionCode(archive) != target.versionCode ||
            archive.versionName != target.version ||
            versionCode(archive) <= versionCode(installed)) throw Failure("TARGET_IDENTITY_MISMATCH")
        val oldSigners = signers(installed)
        if (oldSigners.isEmpty() || oldSigners != signers(archive)) throw Failure("TARGET_SIGNER_MISMATCH")
    }

    private fun supportsDelta(info: ApplicationInfo): Boolean =
        info.splitSourceDirs.isNullOrEmpty() && Build.SUPPORTED_ABIS.contains("arm64-v8a")

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners
            else info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).hex()
        }?.toSet().orEmpty()
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    private fun result(file: File) = mapOf<String, Any>("path" to file.absolutePath, "size" to file.length())
}
