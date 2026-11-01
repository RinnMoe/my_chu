package moe.rinn.mychu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AppUpdateArgumentsTest {
    private val targetSha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private val patchMd5 = "900150983cd24fb0d6963f7d28e17f72"

    private fun mergeArgs(): MutableMap<String, Any?> = mutableMapOf(
        "taskId" to "task-1",
        "versionCode" to 17L,
        "version" to "1.4.0",
        "targetSize" to 2048L,
        "targetHash" to targetSha256,
        "targetHashAlgorithm" to "sha256",
        "patchSize" to 1024L,
        "patchHash" to patchMd5,
        "patchHashAlgorithm" to "md5",
        "patchFormat" to AppUpdateArguments.PATCH_FORMAT,
    )

    private fun withArgs(vararg pairs: Pair<String, Any?>): Map<String, Any?> =
        mergeArgs().apply { for ((key, value) in pairs) put(key, value) }

    private fun withoutArgs(vararg keys: String): Map<String, Any?> =
        mergeArgs().apply { keys.forEach { remove(it) } }

    @Test
    fun mergeAcceptsBothAlgorithmPairs() {
        val request = AppUpdateArguments.merge(mergeArgs())
        assertEquals("task-1", request.target.taskId)
        assertEquals(17L, request.target.versionCode)
        assertEquals("1.4.0", request.target.version)
        assertEquals(2048L, request.target.size)
        assertEquals(targetSha256, request.target.hash)
        assertEquals(HashAlgorithm.SHA256, request.target.algorithm)
        assertEquals(1024L, request.patchSize)
        assertEquals(patchMd5, request.patchHash)
        assertEquals(HashAlgorithm.MD5, request.patchAlgorithm)
        assertNull(request.baseSha256)
    }

    @Test
    fun mergeNormalizesUpstreamBaseHashAndAcceptsAbsence() {
        assertEquals(
            targetSha256,
            AppUpdateArguments.merge(withArgs("baseSha256" to targetSha256.uppercase())).baseSha256,
        )
        assertNull(AppUpdateArguments.merge(withoutArgs("baseSha256")).baseSha256)
        assertNull(AppUpdateArguments.merge(withArgs("baseSha256" to null)).baseSha256)
    }

    @Test
    fun mergeAcceptsOnlyTheSupportedPatchFormat() {
        assertEquals(
            "1.4.0",
            AppUpdateArguments.merge(withArgs("patchFormat" to AppUpdateArguments.PATCH_FORMAT))
                .target.version,
        )
        expectFailure("PATCH_FORMAT_UNSUPPORTED") {
            AppUpdateArguments.merge(withArgs("patchFormat" to "zstd"))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("patchFormat" to 7))
        }
        // The channel always sends the format; a missing field is not a free pass.
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withoutArgs("patchFormat"))
        }
    }

    @Test
    fun mergeRejectsUnknownAlgorithms() {
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("targetHashAlgorithm" to "sha1"))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("targetHashAlgorithm" to "SHA256"))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("patchHashAlgorithm" to null))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withoutArgs("patchHashAlgorithm"))
        }
    }

    @Test
    fun mergeRejectsMalformedHashes() {
        // MD5-length digest declared as SHA-256 and the reverse.
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("targetHash" to patchMd5))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("patchHash" to targetSha256))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("targetHash" to "z".repeat(64)))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("targetHash" to targetSha256.dropLast(1)))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withoutArgs("patchHash")) }
        // The optional upstream base digest is always SHA-256.
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("baseSha256" to patchMd5))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withArgs("baseSha256" to "")) }
    }

    @Test
    fun mergeRejectsBadNumbers() {
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withArgs("versionCode" to 0)) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withArgs("versionCode" to "17")) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withArgs("targetSize" to 0)) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withArgs("patchSize" to -5)) }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("targetSize" to AppUpdateVerifier.MAX_BYTES + 1))
        }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withoutArgs("patchSize")) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withArgs("targetSize" to null)) }
    }

    @Test
    fun versionCodeUsesTheAndroidBoundInsteadOfTheByteCap() {
        val aboveByteCap = AppUpdateVerifier.MAX_BYTES + 1
        assertEquals(
            aboveByteCap,
            AppUpdateArguments.merge(withArgs("versionCode" to aboveByteCap)).target.versionCode,
        )
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("versionCode" to AppUpdateArguments.MAX_VERSION_CODE + 1))
        }
    }

    @Test
    fun mergeRejectsMissingOrEmptyTextArguments() {
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withArgs("version" to "")) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.merge(withoutArgs("taskId")) }
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.merge(withArgs("taskId" to "x".repeat(257)))
        }
    }

    @Test
    fun verifyFullNeedsOnlyTargetArguments() {
        val request = AppUpdateArguments.verifyFull(
            mapOf(
                "taskId" to "task-1",
                "versionCode" to 17,
                "version" to "1.4.0",
                "targetSize" to 2048,
                "targetHash" to targetSha256,
                "targetHashAlgorithm" to "sha256",
            ),
        )
        assertEquals("task-1", request.taskId)
        assertEquals(17L, request.versionCode)
        assertEquals("1.4.0", request.version)
        assertEquals(2048L, request.size)
        assertEquals(targetSha256, request.hash)
        assertEquals(HashAlgorithm.SHA256, request.algorithm)
        expectFailure("INVALID_UPDATE_ARGUMENT") {
            AppUpdateArguments.verifyFull(mapOf("taskId" to "task-1", "versionCode" to 17))
        }
    }

    @Test
    fun taskIdValidationIsSharedWithFinish() {
        assertEquals("task-1", AppUpdateArguments.text(mapOf("taskId" to "task-1"), "taskId"))
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.text(emptyMap<Any, Any>(), "taskId") }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateArguments.text(mapOf("taskId" to 17), "taskId") }
    }
}
