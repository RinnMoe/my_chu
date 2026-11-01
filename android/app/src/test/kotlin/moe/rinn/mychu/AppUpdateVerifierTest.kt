package moe.rinn.mychu

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Shared failure-code assertion for the AppUpdate* JVM tests. */
internal fun expectFailure(code: String, block: () -> Unit) {
    try {
        block()
    } catch (error: AppUpdateEngine.Failure) {
        assertEquals(code, error.code)
        return
    }
    throw AssertionError("expected AppUpdateEngine.Failure($code)")
}

class AppUpdateVerifierTest {
    @get:Rule
    val temporary = TemporaryFolder()

    /** SHA-256("abc"); independently known reference value. */
    private val sha256Abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    /** MD5("abc"); independently known reference value. */
    private val md5Abc = "900150983cd24fb0d6963f7d28e17f72"

    private fun abcFile(): File = temporary.newFile("abc.bin").apply { writeText("abc") }

    @Test
    fun digestsRealFilesWithBothAlgorithms() {
        val file = abcFile()
        assertEquals(sha256Abc, AppUpdateVerifier.digest(file, HashAlgorithm.SHA256))
        assertEquals(md5Abc, AppUpdateVerifier.digest(file, HashAlgorithm.MD5))
    }

    @Test
    fun digestsEmptyFileWithBothAlgorithms() {
        val file = temporary.newFile("empty.bin")
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            AppUpdateVerifier.digest(file, HashAlgorithm.SHA256),
        )
        assertEquals("d41d8cd98f00b204e9800998ecf8427e", AppUpdateVerifier.digest(file, HashAlgorithm.MD5))
    }

    @Test
    fun algorithmParserAcceptsOnlyProtocolTokens() {
        assertEquals(HashAlgorithm.SHA256, HashAlgorithm.parse("sha256"))
        assertEquals(HashAlgorithm.MD5, HashAlgorithm.parse("md5"))
        for (raw in listOf<Any?>(null, "", "sha1", "SHA256", "MD5", "sha-256", 256)) {
            expectFailure("INVALID_UPDATE_ARGUMENT") { HashAlgorithm.parse(raw) }
        }
    }

    @Test
    fun expectedHashRequiresExactAlgorithmLength() {
        assertEquals(sha256Abc, AppUpdateVerifier.parseHash(sha256Abc.uppercase(), HashAlgorithm.SHA256))
        assertEquals(md5Abc, AppUpdateVerifier.parseHash(md5Abc, HashAlgorithm.MD5))
        // Wrong length for the declared algorithm, non-hex digits and non-strings.
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateVerifier.parseHash(md5Abc, HashAlgorithm.SHA256) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateVerifier.parseHash(sha256Abc, HashAlgorithm.MD5) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateVerifier.parseHash(sha256Abc.dropLast(1), HashAlgorithm.SHA256) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateVerifier.parseHash("z".repeat(64), HashAlgorithm.SHA256) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateVerifier.parseHash(null, HashAlgorithm.SHA256) }
        expectFailure("INVALID_UPDATE_ARGUMENT") { AppUpdateVerifier.parseHash(42, HashAlgorithm.MD5) }
    }

    @Test
    fun verifyFileAcceptsMatchingSizeAndDigestForBothAlgorithms() {
        val file = abcFile()
        AppUpdateVerifier.verifyFile(file, 3, sha256Abc, HashAlgorithm.SHA256, "PATCH_HASH_MISMATCH")
        AppUpdateVerifier.verifyFile(file, 3, md5Abc, HashAlgorithm.MD5, "TARGET_HASH_MISMATCH")
        AppUpdateVerifier.verifyFile(file, 3, sha256Abc.uppercase(), HashAlgorithm.SHA256, "PATCH_HASH_MISMATCH")
    }

    @Test
    fun verifyFileReportsPatchAndTargetMismatchesWithTheirOwnCodes() {
        val file = abcFile()
        // Declared size differs from the file.
        expectFailure("PATCH_HASH_MISMATCH") {
            AppUpdateVerifier.verifyFile(file, 4, sha256Abc, HashAlgorithm.SHA256, "PATCH_HASH_MISMATCH")
        }
        expectFailure("TARGET_HASH_MISMATCH") {
            AppUpdateVerifier.verifyFile(file, 2, sha256Abc, HashAlgorithm.SHA256, "TARGET_HASH_MISMATCH")
        }
        // Size matches but the digest belongs to another algorithm.
        expectFailure("PATCH_HASH_MISMATCH") {
            AppUpdateVerifier.verifyFile(file, 3, md5Abc, HashAlgorithm.SHA256, "PATCH_HASH_MISMATCH")
        }
        expectFailure("TARGET_HASH_MISMATCH") {
            AppUpdateVerifier.verifyFile(file, 3, sha256Abc, HashAlgorithm.MD5, "TARGET_HASH_MISMATCH")
        }
        // A missing file is a mismatch, never a crash.
        expectFailure("TARGET_HASH_MISMATCH") {
            AppUpdateVerifier.verifyFile(File(temporary.root, "missing.apk"), 3, sha256Abc, HashAlgorithm.SHA256, "TARGET_HASH_MISMATCH")
        }
    }

    @Test
    fun storageCheckUsesExclusiveMargin() {
        val target = 1000L
        val margin = 500L
        expectFailure("UPDATE_STORAGE") {
            AppUpdateVerifier.checkStorage(target + margin - 1, target, margin)
        }
        AppUpdateVerifier.checkStorage(target + margin, target, margin)
        AppUpdateVerifier.checkStorage(target + margin + 1, target, margin)
    }

    @Test
    fun storageCheckDefaultsToThirtyTwoMebibytes() {
        expectFailure("UPDATE_STORAGE") {
            AppUpdateVerifier.checkStorage(AppUpdateVerifier.STORAGE_MARGIN_BYTES - 1, 0)
        }
        AppUpdateVerifier.checkStorage(AppUpdateVerifier.STORAGE_MARGIN_BYTES, 0)
    }

    @Test
    fun readableSourceRequiresNonEmptyRegularFile() {
        val source = temporary.newFile("source.apk").apply { writeText("apk") }
        val empty = temporary.newFile("empty.apk")
        assertTrue(AppUpdateVerifier.readableSource(source))
        assertFalse(AppUpdateVerifier.readableSource(empty))
        assertFalse(AppUpdateVerifier.readableSource(File(temporary.root, "missing.apk")))
        assertFalse(AppUpdateVerifier.readableSource(temporary.newFolder("directory.apk")))
    }
}
