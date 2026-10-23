package moe.rinn.mychu.courselive

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private const val OWNER = "0123456789abcdef0123456789abcdef0123456789abcdef"

private fun block(
    id: String = "course",
    start: Long,
    end: Long,
    lead: Long = 30L * 60 * 1000,
    name: String = "高等数学",
    location: String = "WM101",
) = CourseLiveBlock(
    eventId = id,
    name = name,
    location = location,
    startAt = start,
    endAt = end,
    windowStart = start - lead,
)

private fun blockJson(
    eventId: String = "course",
    startAt: Long = 1_000L,
    endAt: Long = 2_000L,
    lead: Long = 30L * 60 * 1000,
    windowStart: Long = startAt - lead,
    windowEnd: Long = startAt,
    name: String = "高等数学",
): JSONObject = JSONObject()
    .put("eventId", eventId)
    .put("name", name)
    .put("location", "WM101")
    .put("businessDate", "2026-10-16")
    .put("startAt", startAt)
    .put("endAt", endAt)
    .put("windowStart", windowStart)
    .put("windowEnd", windowEnd)

private fun planJson(
    owner: String = OWNER,
    generation: Long = 3,
    courses: List<JSONObject>,
    version: Int = CourseLivePlan.VERSION,
): JSONObject = JSONObject()
    .put("version", version)
    .put("owner", owner)
    .put("generation", generation)
    .put("generatedAt", 0L)
    .put("windowStart", 0L)
    .put("windowEnd", 9_999_999L)
    .put("leadMinutes", 30)
    .put("targetAppId", "feature.academic.schedule")
    .put("courses", JSONArray(courses))

class CourseLivePlanParsingTest {
    @Test
    fun `plan requires the supported version and a valid owner token`() {
        assertNull(
            CourseLivePlan.fromRaw(
                planJson(courses = listOf(blockJson()), version = 2),
            ),
        )
        assertNull(CourseLivePlan.fromRaw(planJson(owner = "short", courses = listOf(blockJson()))))
        assertNotNull(CourseLivePlan.fromRaw(planJson(courses = listOf(blockJson()))))
    }

    @Test
    fun `blocks without identity, name or a positive duration are rejected`() {
        assertNull(CourseLiveBlock.parse(blockJson(eventId = "")))
        assertNull(CourseLiveBlock.parse(blockJson(name = "  ")))
        assertNull(CourseLiveBlock.parse(blockJson(startAt = 2_000L, endAt = 2_000L)))
        assertNull(CourseLiveBlock.parse(blockJson(startAt = -1L)))
    }

    @Test
    fun `a window wider than the course is rejected but an exact window is kept`() {
        assertNull(
            CourseLiveBlock.parse(
                blockJson(startAt = 1_000L, endAt = 2_000L, windowStart = 1_500L),
            ),
        )
        assertNull(
            CourseLiveBlock.parse(
                blockJson(startAt = 1_000L, endAt = 2_000L, windowEnd = 1_500L),
            ),
        )
        val exact = CourseLiveBlock.parse(
            blockJson(startAt = 1_000L, endAt = 2_000L, lead = 0L),
        )
        assertNotNull(exact)
    }

    @Test
    fun `duplicate occurrences collapse to the earliest block`() {
        val plan = CourseLivePlan.fromRaw(
            planJson(
                courses = listOf(
                    blockJson(eventId = "a", startAt = 1_000L, endAt = 2_000L),
                    blockJson(eventId = "a", startAt = 3_000L, endAt = 4_000L),
                    blockJson(eventId = "b", startAt = 5_000L, endAt = 6_000L),
                ),
            ),
        )
        assertEquals(listOf("a", "b"), plan!!.blocks.map { it.eventId })
        assertEquals(1_000L, plan.blocks.first().startAt)
    }

    @Test
    fun `a plan with any unusable course is rejected as a whole`() {
        // Dropping a malformed entry would silently move or revoke an activity,
        // so the device keeps its previous plan instead.
        val invalid = CourseLivePlan.fromRaw(
            planJson(
                courses = listOf(
                    blockJson(eventId = "ok", startAt = 1_000L, endAt = 2_000L),
                    blockJson(eventId = "bad", startAt = 3_000L, endAt = 3_000L),
                ),
            ),
        )
        assertNull(invalid)
        assertNull(CourseLivePlan.fromRaw(planJson(courses = emptyList())))
    }

    @Test
    fun `phase boundaries are half open at start and end`() {
        val unit = block(start = 10_000L, end = 20_000L, lead = 1_000L)
        assertEquals(CourseLivePhase.IDLE, unit.phaseAt(8_999L))
        assertEquals(CourseLivePhase.PRE, unit.phaseAt(9_000L))
        assertEquals(CourseLivePhase.PRE, unit.phaseAt(9_999L))
        assertEquals(CourseLivePhase.ONGOING, unit.phaseAt(10_000L))
        assertEquals(CourseLivePhase.ONGOING, unit.phaseAt(19_999L))
        assertEquals(CourseLivePhase.ENDED, unit.phaseAt(20_000L))
    }

    @Test
    fun `legacy v1 windows normalize without losing the account fence`() {
        val plan = CourseLivePlan.fromRaw(planJson(courses = listOf(
            blockJson(startAt = 10_000L, endAt = 20_000L, windowEnd = 20_000L),
        )))!!
        assertEquals(OWNER, plan.owner)
        assertEquals(3L, plan.generation)
        assertEquals(10_000L, plan.blocks.single().startAt)
        assertEquals(CourseLivePhase.ONGOING, plan.blocks.single().phaseAt(10_000L))
    }

}


class CourseLiveScheduleTest {
    @Test fun `opening start and end are independent exact boundaries`() {
        val unit = block(start = 130_000L, end = 1_500_000L, lead = 30_000L)
        for ((now, boundary) in listOf(0L to 100_000L, 100_000L to 130_000L,
            130_000L to 1_500_000L, 1_500_000L to null)) {
            assertEquals(boundary, CourseLiveSchedule.nextChangeAt(unit, now))
        }
    }
    @Test fun `ongoing course wins over a future pre-class course`() {
        val current = block(id = "A", start = 100_000L, end = 900_000L)
        val upcoming = block(id = "B", start = 500_000L, end = 1_000_000L)
        assertEquals("A", CourseLiveSchedule.selectBlock(listOf(upcoming, current), 200_000L) { false }?.eventId)
        assertEquals("B", CourseLiveSchedule.selectBlock(listOf(current, upcoming), 900_000L) { false }?.eventId)
    }
    @Test fun `pre-class selects nearest start and ties use stable identity`() {
        val a = block(id = "A", start = 400_000L, end = 900_000L)
        val b = block(id = "B", start = 500_000L, end = 900_000L)
        assertEquals("A", CourseLiveSchedule.selectBlock(listOf(b, a), 300_000L) { false }?.eventId)
        assertEquals("B", CourseLiveSchedule.selectBlock(listOf(a, b), 300_000L) { it.eventId == "A" }?.eventId)
    }
}

class CourseLiveDisplayResolverTest {
    @Test fun `progress derives from real elapsed time and ends half open`() {
        val unit = block(start = 100_000L, end = 900_000L)
        val before = CourseLiveDisplayResolver.decide(listOf(unit), 99_999L, emptySet()) as CourseLiveDecision.Post
        assertNull(before.display.progress)
        val ongoing = CourseLiveDisplayResolver.decide(listOf(unit), 500_000L, emptySet()) as CourseLiveDecision.Post
        assertEquals(50, ongoing.display.progress)
        assertEquals(CourseLivePhase.ONGOING, ongoing.display.phase)
        assertTrue(CourseLiveDisplayResolver.decide(listOf(unit), 900_000L, emptySet()) is CourseLiveDecision.Cancel)
    }
    @Test fun `dismissed occurrence stays absent through both stages`() {
        val unit = block(id = "A", start = 100_000L, end = 900_000L)
        for (now in listOf(99_999L, 500_000L)) {
            assertTrue(CourseLiveDisplayResolver.decide(listOf(unit), now, setOf("A")) is CourseLiveDecision.Cancel)
            assertNull(CourseLiveDisplayResolver.nextBoundaryAt(listOf(unit), now, setOf("A")))
        }
    }
}

class CourseLiveCoordinatorTest {
    private fun session(blocks: List<CourseLiveBlock>, shown: String? = null,
        ledger: Map<String, Long> = emptyMap()) = CourseLiveSession(OWNER, 3, blocks, ledger, shown)
    @Test fun `same activity transitions to progress without ending at course start`() {
        val unit = block(id = "A", start = 100_000L, end = 900_000L)
        val before = CourseLiveCoordinator.coordinate(session(listOf(unit)), 99_000L, true)
        assertNull(before.post!!.progress)
        assertEquals(801_000L, before.post!!.timeoutMillis)
        val after = CourseLiveCoordinator.coordinate(session(listOf(unit), "A"), 100_000L, true)
        assertEquals("A", after.post!!.eventId)
        assertEquals(0, after.post!!.progress)
        assertFalse(after.endFirst)
        assertEquals(900_000L, after.nextBoundaryAt)
    }
    @Test fun `progress checkpoint never replaces the exact end boundary`() {
        val unit = block(start = 100_000L, end = 900_000L)
        val effect = CourseLiveCoordinator.coordinate(session(listOf(unit)), 500_000L, true)
        assertEquals(900_000L, effect.nextBoundaryAt)
        assertEquals(600_000L, effect.nextCheckpointAt)
        val last = CourseLiveCoordinator.coordinate(session(listOf(unit)), 899_999L, true)
        assertNull(last.nextCheckpointAt)
        assertEquals(1L, last.post!!.timeoutMillis)
    }
    @Test fun `ended overlap hands off to remaining ongoing course`() {
        val blocks = listOf(block(id = "A", start = 100_000L, end = 600_000L),
            block(id = "B", start = 300_000L, end = 900_000L))
        val effect = CourseLiveCoordinator.coordinate(session(blocks, "A"), 600_000L, true)
        assertEquals("B", effect.post!!.eventId)
        assertEquals(50, effect.post!!.progress)
        assertTrue(effect.endFirst)
    }
    @Test fun `end cancels display and both reservations`() {
        val effect = CourseLiveCoordinator.coordinate(session(listOf(block(start = 100_000L, end = 900_000L)), "course"), 900_000L, true)
        assertTrue(effect.cancelDisplay)
        assertTrue(effect.forgetDisplay)
        assertNull(effect.nextBoundaryAt)
        assertNull(effect.nextCheckpointAt)
    }
    @Test fun `dismissal survives transition while expired ledger is pruned`() {
        val blocks = listOf(block(start = 100_000L, end = 900_000L))
        val dismissed = CourseLiveCoordinator.coordinate(session(blocks, "course", mapOf("course" to 1_000_000L)), 500_000L, true)
        assertNull(dismissed.post)
        assertNull(dismissed.nextBoundaryAt)
        val expired = CourseLiveCoordinator.coordinate(session(blocks, ledger = mapOf("course" to 400_000L)), 500_000L, true)
        assertTrue(expired.prunedDismissals)
        assertNotNull(expired.post)
    }
    @Test fun `ending one occurrence immediately selects another ongoing course`() {
        val blocks = listOf(block(id = "A", start = 100_000L, end = 900_000L),
            block(id = "B", start = 300_000L, end = 1_200_000L))
        val effect = CourseLiveCoordinator.coordinate(
            session(blocks, "A", mapOf("A" to 2_000_000L)), 500_000L, true)
        assertEquals("B", effect.post!!.eventId)
        assertTrue(effect.endFirst)
        assertEquals(1_200_000L, effect.nextBoundaryAt)
        assertEquals(600_000L, effect.nextCheckpointAt)
    }
    @Test fun `missing permission or owner removes all activity work`() {
        for (session in listOf(session(listOf(block(start = 100_000L, end = 900_000L)), "course"),
            CourseLiveSession(null, 0, emptyList()))) {
            val effect = CourseLiveCoordinator.coordinate(session, 500_000L, false)
            assertTrue(effect.cancelDisplay)
            assertNull(effect.post)
            assertNull(effect.nextBoundaryAt)
            assertNull(effect.nextCheckpointAt)
        }
    }
    @Test fun `before window only opening is reserved`() {
        val effect = CourseLiveCoordinator.coordinate(session(listOf(block(start = 100_000L, end = 900_000L, lead = 10_000L))), 1L, true)
        assertNull(effect.post)
        assertEquals(90_000L, effect.nextBoundaryAt)
        assertNull(effect.nextCheckpointAt)
    }
}

class CourseLiveNotificationIdentityTest {
    @Test
    fun `identities avoid the retired live-notification ids`() {
        // The retired Android live notification used ids 480001-480003 and
        // alarm request codes from 480100 upwards.
        assertTrue(CourseLiveNotificationIdentity.NOTIFICATION_ID < 480001)
        assertTrue(CourseLiveNotificationIdentity.ALARM_REQUEST < 480100)
        assertTrue(CourseLiveNotificationIdentity.CONTENT_REQUEST < 480100)
        assertFalse(CourseLiveNotificationIdentity.CHANNEL_ID == "mychu_live_course")
    }

    @Test
    fun `one fixed slot is shared by every ownership lineage`() {
        // The slot must not depend on the owner: ownership can change while no
        // Flutter engine is attached, and a per-owner tag would strand the
        // previous account's notification on the shade.
        assertEquals("mychu-course-live", CourseLiveNotificationIdentity.TAG)
        assertFalse(CourseLiveNotificationIdentity.TAG.contains("://"))
    }

    @Test
    fun `dismiss and alarm actions are distinct from retired actions`() {
        val actions = setOf(
            CourseLiveReceiver.ACTION_DISMISSED,
            CourseLiveRecoveryReceiver.ACTION_EXACT_ALARM_PERMISSION_CHANGED,
        )
        assertFalse(actions.contains("moe.rinn.mychu.action.LIVE_UPDATE_REFRESH"))
        assertFalse(actions.contains("moe.rinn.mychu.action.SCHEDULED_ALERT_DELIVER"))
    }
}
