package moe.rinn.mychu.desktopwidgets

import java.time.Instant
import java.time.LocalDate
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class RecentScheduleSnapshotParserTest {
    private fun snapshot(status: String = "ready", recentCourses: Boolean = true): String {
        val course = JSONObject().put("id", "roomis:one").put("name", "Actual Wednesday")
            .put("location", "Room A").put("start", "2026-10-10T00:30:00Z")
            .put("end", "2026-10-10T01:15:00Z").put("startPeriod", 1).put("endPeriod", 1)
        val academic = JSONObject().put("id", "academic:one").put("courseName", "Ordinary Saturday")
            .put("location", "Room B").put("date", "2026-10-10")
            .put("startPeriod", 1).put("endPeriod", 1).put("periodLabel", "1")
            .put("startTime", "08:30").put("endTime", "09:15")
        return JSONObject().put("schemaVersion", 1).put("timezoneOffsetMinutes", 480)
            .put("generatedAt", "2026-10-10T00:00:00Z")
            .put("schedule", JSONObject().put("status", status)
                .put("semesterId", "term").put("firstWeekStartDate", "2026-09-07")
                .put("maxWeek", 20).put("occurrences", if (status == "ready") JSONArray().put(academic) else JSONArray()))
            .put("recentSchedule", JSONObject().put("startDate", "2026-10-10").put("endDate", "2026-10-16")
                .put("fetchedAt", "2026-10-10T00:00:00Z").put("fresh", true)
                .put("courses", if (recentCourses) JSONArray().put(course) else JSONArray())).toString()
    }

    @Test fun `today uses actual dated courses but week stays academic`() {
        val source = snapshot()
        val now = Instant.parse("2026-10-10T00:00:00Z")
        assertEquals(listOf("Actual Wednesday"), TodayScheduleSnapshotParser.parseForNow(source, now).courses.map { it.courseName })
        assertEquals(listOf("Ordinary Saturday"), WeekScheduleSnapshotParser.parse(source, now).days[5].flatMap { it.courses }.map { it.courseName })
        assertEquals("08:30–09:15", TodayScheduleSnapshotParser.parseForNow(source, now).courses.single().displayTime)
    }

    @Test fun `covered empty and calendar unavailable do not restore academic courses`() {
        assertEquals(emptyList<TodayScheduleCourse>(), TodayScheduleSnapshotParser.parse(snapshot(recentCourses = false), LocalDate.parse("2026-10-10")).courses)
        assertEquals(TodayScheduleStatus.READY, TodayScheduleSnapshotParser.parse(snapshot(status = "calendarUnavailable"), LocalDate.parse("2026-10-10")).status)
    }

    @Test fun `midnight selects cached date and completed courses remain hidden`() {
        val source = snapshot()
        assertEquals(LocalDate.parse("2026-10-10"), TodayScheduleSnapshotParser.parseForNow(source, Instant.parse("2026-10-09T16:01:00Z")).businessDate)
        assertEquals(emptyList<TodayScheduleCourse>(), TodayScheduleSnapshotParser.parseForNow(source, Instant.parse("2026-10-10T01:15:00Z")).courses)
        assertEquals(emptyList<TodayScheduleCourse>(), TodayScheduleSnapshotParser.parse(source, LocalDate.parse("2026-10-11")).courses)
        assertEquals(TodayScheduleStatus.SIGNED_OUT, TodayScheduleSnapshotParser.parse(snapshot(status = "signedOut"), LocalDate.parse("2026-10-10")).status)
    }
}
