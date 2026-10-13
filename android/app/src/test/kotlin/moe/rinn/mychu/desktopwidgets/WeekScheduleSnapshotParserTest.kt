package moe.rinn.mychu.desktopwidgets

import java.time.Instant
import java.time.LocalDate
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WeekScheduleSnapshotParserTest {
    private fun snapshot(first: String = "2026-09-07", max: Int = 20) = """
        {"schemaVersion":1,"timezoneOffsetMinutes":480,"generatedAt":"2026-09-07T00:00:00Z",
         "schedule":{"status":"ready","semesterId":"term","currentWeek":1,
          "firstWeekStartDate":"$first","maxWeek":$max,"occurrences":[
           {"id":"a","date":"2026-09-27","courseName":"周日课程","location":"A","startPeriod":9,"endPeriod":11,"periodLabel":"9–11","startTime":"19:00","endTime":"21:25"},
           {"id":"b","date":"2026-09-28","courseName":"数学","location":"B","startPeriod":1,"endPeriod":2,"periodLabel":"1–2","startTime":"08:30","endTime":"10:05"},
           {"id":"c","date":"2026-09-28","courseName":"冲突","location":"C","startPeriod":2,"endPeriod":3,"periodLabel":"2–3"},
           {"id":"d","date":"2026-10-04","courseName":"周末课程","location":"D","startPeriod":11,"endPeriod":11,"periodLabel":"11"}
          ]}}
    """.trimIndent()

    @Test fun `east eight switches week at Monday midnight and retains completed courses`() {
        val sunday = WeekScheduleSnapshotParser.parse(snapshot(), Instant.parse("2026-09-27T15:59:59Z"))
        assertEquals(LocalDate.parse("2026-09-21"), sunday.weekStart)
        assertEquals(3, sunday.currentWeek)
        assertEquals("周日课程", sunday.days[6].single().courses.single().courseName)
        val monday = WeekScheduleSnapshotParser.parse(snapshot(), Instant.parse("2026-09-27T16:00:00Z"))
        assertEquals(LocalDate.parse("2026-09-28"), monday.weekStart)
        assertEquals(4, monday.currentWeek)
        assertEquals(2, monday.days[0].single().courses.size)
        assertEquals(3, monday.days[0].single().endPeriod)
        assertEquals(11, monday.days[6].single().startPeriod)
        val evening = WeekScheduleSnapshotParser.parse(snapshot(), Instant.parse("2026-09-28T15:00:00Z"))
        assertEquals(monday.days, evening.days)
    }

    @Test fun `old metadata remains valid for today and unavailable for week`() {
        val root = JSONObject(snapshot())
        root.getJSONObject("schedule").remove("firstWeekStartDate")
        root.getJSONObject("schedule").remove("maxWeek")
        val now = Instant.parse("2026-09-28T00:00:00Z")
        assertEquals(TodayScheduleStatus.READY, TodayScheduleSnapshotParser.parseForNow(root.toString(), now).status)
        assertEquals(WeekScheduleStatus.UNAVAILABLE, WeekScheduleSnapshotParser.parse(root.toString(), now).status)
    }

    @Test fun `empty teaching week and outside term are distinct`() {
        assertEquals(WeekScheduleStatus.OUTSIDE_TERM, WeekScheduleSnapshotParser.parse(snapshot(), Instant.parse("2026-09-06T00:00:00Z")).status)
        assertEquals(WeekScheduleStatus.OUTSIDE_TERM, WeekScheduleSnapshotParser.parse(snapshot(max = 1), Instant.parse("2026-09-14T00:00:00Z")).status)
        val empty = WeekScheduleSnapshotParser.parse(snapshot(), Instant.parse("2026-09-14T00:00:00Z"))
        assertEquals(WeekScheduleStatus.READY, empty.status)
        assertTrue(empty.days.all { it.isEmpty() })
    }

    @Test fun `year boundary advances academic week independently from generated label`() {
        val result = WeekScheduleSnapshotParser.parse(snapshot(first = "2026-12-28"), Instant.parse("2027-01-03T16:00:00Z"))
        assertEquals(LocalDate.parse("2027-01-04"), result.weekStart)
        assertEquals(2, result.currentWeek)
    }

    @Test fun `signed out ignores cached calendar and courses`() {
        val root = JSONObject(snapshot())
        root.getJSONObject("schedule").put("status", "signedOut")
        val result = WeekScheduleSnapshotParser.parse(root.toString(), Instant.parse("2026-09-28T00:00:00Z"))
        assertEquals(WeekScheduleStatus.SIGNED_OUT, result.status)
        assertTrue(result.days.all { it.isEmpty() })
        assertNull(result.currentWeek)
    }

    @Test fun `malformed calendar and unsupported snapshot are rejected`() {
        assertThrows(Exception::class.java) { WeekScheduleSnapshotParser.parse(snapshot(first = "2026-09-08"), Instant.now()) }
        assertThrows(Exception::class.java) { WeekScheduleSnapshotParser.parse(snapshot().replace("\"schemaVersion\":1", "\"schemaVersion\":9"), Instant.now()) }
    }

    @Test fun `refresh uses future course boundary or midnight`() {
        val now = Instant.parse("2026-09-28T01:00:00Z")
        val end = now.plusSeconds(60)
        val midnight = Instant.parse("2026-09-28T16:00:00Z")
        assertEquals(end, DesktopWidgetScheduler.nextRefresh(now, midnight, listOf(now.minusSeconds(1), end)))
        assertEquals(midnight, DesktopWidgetScheduler.nextRefresh(now, midnight, emptyList()))
    }

    @Test fun `course colors use the same UTF sixteen hash as Harmony`() {
        assertEquals(4, WeekScheduleSnapshotParser.colorIndex("数学"))
        assertEquals(3, WeekScheduleSnapshotParser.colorIndex("高等数学"))
        assertEquals(4, WeekScheduleSnapshotParser.colorIndex("🧪实验"))
    }
}
