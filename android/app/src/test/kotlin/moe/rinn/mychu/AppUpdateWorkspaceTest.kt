package moe.rinn.mychu

import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AppUpdateWorkspaceTest {
    @get:Rule
    val temporary = TemporaryFolder()

    private lateinit var root: File
    private lateinit var source: File
    private lateinit var workspace: AppUpdateWorkspace

    /** Fixed clock so retention boundaries are deterministic. */
    private var clock = 1_700_000_000_000L

    @Before
    fun setUp() {
        root = temporary.newFolder("app_updates")
        source = temporary.newFile("source.apk").apply { writeText("installed-apk") }
        workspace = AppUpdateWorkspace(root, now = { clock })
    }

    private fun taskDirectory(): File =
        File(root, UUID.randomUUID().toString()).apply { mkdirs() }

    @Test
    fun beginCreatesUuidTaskDirectoryWithStableFileNames() {
        val session = workspace.begin(source, "captured-hash")
        assertEquals(root, session.directory.parentFile)
        assertEquals(session.taskId, session.directory.name)
        assertEquals(session.taskId, UUID.fromString(session.taskId).toString())
        assertEquals("update.hdiff", session.patch.name)
        assertEquals("full.apk", session.full.name)
        assertEquals("target.apk", session.output.name)
        assertEquals(session.directory, session.patch.parentFile)
        assertEquals(source, workspace.session(session.taskId).source)
        assertEquals("captured-hash", workspace.session(session.taskId).sourceHash)
    }

    @Test
    fun finishReleasesTheTaskSlotForTheNextTask() {
        val first = workspace.begin(source, "h1")
        workspace.finish(first.taskId, false)
        val second = workspace.begin(source, "h3")
        assertNotEquals(first.taskId, second.taskId)
    }

    @Test
    fun prepareRejectsASecondLiveTask() {
        workspace.begin(source, "h")
        expectFailure("UPDATE_BUSY") { workspace.prepare() }
    }

    @Test
    fun unknownTaskIdIsRejected() {
        expectFailure("INVALID_UPDATE_TASK") {
            workspace.session("00000000-0000-0000-4000-8000-000000000000")
        }
    }

    @Test
    fun cleanupExpiresOnlyOurOwnOldDirectories() {
        val expired = taskDirectory()
        expired.setLastModified(clock - AppUpdateWorkspace.RETENTION_MS - 1)
        val recent = taskDirectory()
        recent.setLastModified(clock - 1_000)
        val unrelated = File(root, "not-a-task").apply { mkdirs() }
        unrelated.setLastModified(clock - 10 * AppUpdateWorkspace.RETENTION_MS)
        val uppercaseName = File(root, UUID.randomUUID().toString().uppercase()).apply { mkdirs() }
        uppercaseName.setLastModified(clock - 10 * AppUpdateWorkspace.RETENTION_MS)
        val strayFile = File(root, "stray.txt").apply { writeText("x") }
        strayFile.setLastModified(clock - 10 * AppUpdateWorkspace.RETENTION_MS)

        workspace.cleanup()

        assertFalse(expired.exists())
        assertTrue(recent.isDirectory)
        assertTrue(unrelated.isDirectory)
        assertTrue(uppercaseName.isDirectory)
        assertTrue(strayFile.isFile)
    }

    @Test
    fun cleanupKeepsLiveSessionDirectoryEvenWhenExpired() {
        val session = workspace.begin(source, "h")
        session.directory.setLastModified(clock - 10 * AppUpdateWorkspace.RETENTION_MS)
        workspace.cleanup()
        assertTrue(session.directory.isDirectory)
        assertEquals("h", workspace.session(session.taskId).sourceHash)
    }

    @Test
    fun cleanupDoesNotFollowSymlinkedTaskDirectory() {
        val outside = temporary.newFolder("outside")
        val keep = File(outside, "keep.txt").apply { writeText("keep") }
        val link = File(root, UUID.randomUUID().toString())
        val created = try {
            Files.createSymbolicLink(link.toPath(), outside.toPath())
            true
        } catch (error: Exception) {
            false
        }
        Assume.assumeTrue("symbolic link creation is unavailable on this host", created)

        workspace.cleanup()

        assertTrue(keep.isFile)
        assertTrue(Files.exists(link.toPath(), LinkOption.NOFOLLOW_LINKS))
    }

    @Test
    fun finishWithRetainedApkKeepsOnlyTheTarget() {
        val session = workspace.begin(source, "h")
        session.patch.writeText("patch")
        session.full.writeText("full")
        session.output.writeText("target")
        File(session.directory, "extra.tmp").writeText("scratch")

        workspace.finish(session.taskId, true)

        assertEquals(listOf("target.apk"), session.directory.listFiles()?.map { it.name })
        assertTrue(kotlin.math.abs(session.directory.lastModified() - clock) < 5_000)
        expectFailure("INVALID_UPDATE_TASK") { workspace.session(session.taskId) }
    }

    @Test
    fun finishWithoutRetainingRemovesTheTaskDirectory() {
        val session = workspace.begin(source, "h")
        session.output.writeText("target")
        workspace.finish(session.taskId, false)
        assertFalse(session.directory.exists())
    }

    @Test
    fun finishOfUnknownTaskIsIgnored() {
        workspace.finish("00000000-0000-0000-4000-8000-000000000000", true)
        workspace.finish("00000000-0000-0000-4000-8000-000000000000", false)
        assertTrue(root.isDirectory)
    }

    @Test
    fun beginReportsStorageFailureWhenDirectoryCannotBeCreated() {
        val blockedRoot = temporary.newFile("blocked")
        val blocked = AppUpdateWorkspace(blockedRoot, now = { clock })
        expectFailure("UPDATE_STORAGE") { blocked.begin(source, "h") }
    }

    @Test
    fun availableBytesUsesRootThenItsParent() {
        assertTrue(workspace.availableBytes() > 0)
        root.deleteRecursively()
        assertTrue(workspace.availableBytes() > 0)
    }
}
