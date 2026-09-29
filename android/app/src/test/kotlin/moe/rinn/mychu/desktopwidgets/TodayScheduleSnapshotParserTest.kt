package moe.rinn.mychu.desktopwidgets

import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.json.JSONException

class TodayScheduleSnapshotParserTest {
    @Test
    fun `today is selected in east eight regardless of device timezone`() {
        val snapshot = snapshot(
            status = "ready",
            semesterId = "term-1",
            occurrences = listOf(
                occurrence("2026-09-27", "昨天的课程", 1, 1),
                occurrence("2026-09-28", "高等数学", 1, 2),
            ),
        )

        val result = TodayScheduleSnapshotParser.parseForNow(
            snapshot,
            Instant.parse("2026-09-27T16:30:00Z"),
        )

        assertEquals(LocalDate.parse("2026-09-28"), result.businessDate)
        assertEquals(listOf("高等数学"), result.courses.map { it.courseName })
    }

    @Test
    fun `courses sort by period and keep period fallback when time is absent`() {
        val result = TodayScheduleSnapshotParser.parse(
            snapshot(
                status = "ready",
                semesterId = "term-1",
                occurrences = listOf(
                    occurrence("2026-09-28", "英语", 3, 4),
                    occurrence("2026-09-28", "数学", 1, 2, startTime = null, endTime = null),
                ),
            ),
            LocalDate.parse("2026-09-28"),
        )

        assertEquals(listOf("数学", "英语"), result.courses.map { it.courseName })
        assertEquals("第1–2节", result.courses.first().displayTime)
        assertEquals("10:00–11:40", result.courses.last().displayTime)
    }

    @Test
    fun `reads optional current academic week`() {
        val result = TodayScheduleSnapshotParser.parse(
            snapshot(
                status = "ready",
                semesterId = "term-1",
                occurrences = emptyList(),
                currentWeek = 5,
            ),
            LocalDate.parse("2026-09-28"),
        )

        assertEquals(5, result.currentWeek)
    }

    @Test
    fun `unavailable schedule states never show occurrences`() {
        val cases = mapOf(
            "signedOut" to TodayScheduleStatus.SIGNED_OUT,
            "noSchedule" to TodayScheduleStatus.NO_SCHEDULE,
            "calendarUnavailable" to TodayScheduleStatus.CALENDAR_UNAVAILABLE,
        )
        for ((status, expected) in cases) {
            val result = TodayScheduleSnapshotParser.parse(
                snapshot(status = status, semesterId = null, occurrences = emptyList()),
                LocalDate.parse("2026-09-28"),
            )
            assertEquals(expected, result.status)
            assertEquals(emptyList<TodayScheduleCourse>(), result.courses)
        }
    }

    @Test
    fun `unsupported schema is rejected`() {
        val snapshot = snapshot(
            status = "ready",
            semesterId = "term-1",
            occurrences = emptyList(),
        ).replace("\"schemaVersion\": 1", "\"schemaVersion\": 2")

        assertThrows(JSONException::class.java) {
            TodayScheduleSnapshotParser.parse(snapshot, LocalDate.parse("2026-09-28"))
        }
    }

    private fun snapshot(
        status: String,
        semesterId: String?,
        occurrences: List<String>,
        currentWeek: Int? = null,
    ): String = """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-09-27T16:30:00.000Z",
          "timezoneOffsetMinutes": 480,
          "schedule": {
            "status": "$status",
            ${semesterId?.let { "\"semesterId\": \"$it\"," } ?: ""}
            ${currentWeek?.let { "\"currentWeek\": $it," } ?: ""}
            "occurrences": [${occurrences.joinToString(",")}]
          },
          "shortcuts": []
        }
    """.trimIndent()

    private fun occurrence(
        date: String,
        name: String,
        startPeriod: Int,
        endPeriod: Int,
        startTime: String? = "10:00",
        endTime: String? = "11:40",
    ): String = """
        {
          "id": "$date|0",
          "date": "$date",
          "courseName": "$name",
          "location": "教学楼A101",
          "startPeriod": $startPeriod,
          "endPeriod": $endPeriod,
          "periodLabel": "第${startPeriod}–${endPeriod}节",
          "startTime": ${startTime?.let { "\"$it\"" } ?: "null"},
          "endTime": ${endTime?.let { "\"$it\"" } ?: "null"}
        }
    """.trimIndent()
}
