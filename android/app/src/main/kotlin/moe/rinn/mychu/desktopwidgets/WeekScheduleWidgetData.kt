package moe.rinn.mychu.desktopwidgets

import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import org.json.JSONException
import org.json.JSONObject

internal enum class WeekScheduleStatus {
    SIGNED_OUT, NO_SCHEDULE, CALENDAR_UNAVAILABLE, READY, UNAVAILABLE, OUTSIDE_TERM,
}

internal data class WeekCourseBlock(
    val startPeriod: Int,
    val endPeriod: Int,
    val courses: List<TodayScheduleCourse>,
)

internal data class WeekScheduleWidgetData(
    val businessDate: LocalDate,
    val weekStart: LocalDate,
    val status: WeekScheduleStatus,
    val currentWeek: Int? = null,
    val days: List<List<WeekCourseBlock>> = List(7) { emptyList() },
)

internal object WeekScheduleSnapshotParser {
    fun unavailable(now: Instant): WeekScheduleWidgetData {
        val date = TodayScheduleSnapshotParser.businessDate(now)
        return WeekScheduleWidgetData(date, date.minusDays(date.dayOfWeek.value - 1L), WeekScheduleStatus.UNAVAILABLE)
    }

    fun parse(source: String, now: Instant): WeekScheduleWidgetData {
        val initial = unavailable(now)
        // Reuse V1 validation, but never pass now when selecting week courses:
        // completed courses remain part of the weekly overview.
        val today = TodayScheduleSnapshotParser.parse(source, initial.businessDate, academicOnly = true)
        val status = when (today.status) {
            TodayScheduleStatus.SIGNED_OUT -> WeekScheduleStatus.SIGNED_OUT
            TodayScheduleStatus.NO_SCHEDULE -> WeekScheduleStatus.NO_SCHEDULE
            TodayScheduleStatus.CALENDAR_UNAVAILABLE -> WeekScheduleStatus.CALENDAR_UNAVAILABLE
            TodayScheduleStatus.READY -> WeekScheduleStatus.READY
            TodayScheduleStatus.UNAVAILABLE -> WeekScheduleStatus.UNAVAILABLE
        }
        if (status != WeekScheduleStatus.READY) return initial.copy(status = status)
        val schedule = JSONObject(source).getJSONObject("schedule")
        if (!schedule.has("firstWeekStartDate") || !schedule.has("maxWeek")) return initial
        val firstWeek = try {
            LocalDate.parse(schedule.getString("firstWeekStartDate"))
        } catch (_: RuntimeException) {
            throw JSONException("Invalid first week date")
        }
        val maxWeek = schedule.getInt("maxWeek")
        if (firstWeek.dayOfWeek.value != 1 || maxWeek < 1) throw JSONException("Invalid week calendar")
        val daysSinceStart = ChronoUnit.DAYS.between(firstWeek, initial.businessDate)
        if (daysSinceStart < 0 || daysSinceStart >= maxWeek.toLong() * 7) {
            return initial.copy(status = WeekScheduleStatus.OUTSIDE_TERM)
        }
        val days = (0L..6L).map { offset ->
            val courses = TodayScheduleSnapshotParser.parse(source, initial.weekStart.plusDays(offset), academicOnly = true).courses
            if (courses.any { it.endPeriod > 11 }) throw JSONException("Invalid week course periods")
            mergeOverlapping(courses)
        }
        return initial.copy(status = status, currentWeek = (daysSinceStart / 7 + 1).toInt(), days = days)
    }

    fun mergeOverlapping(courses: List<TodayScheduleCourse>): List<WeekCourseBlock> {
        val result = mutableListOf<WeekCourseBlock>()
        for (course in courses.sortedWith(compareBy<TodayScheduleCourse> { it.startPeriod }.thenBy { it.endPeriod }.thenBy { it.courseName })) {
            val previous = result.lastOrNull()
            if (previous != null && course.startPeriod <= previous.endPeriod) {
                result[result.lastIndex] = previous.copy(
                    endPeriod = maxOf(previous.endPeriod, course.endPeriod),
                    courses = previous.courses + course,
                )
            } else {
                result.add(WeekCourseBlock(course.startPeriod, course.endPeriod, listOf(course)))
            }
        }
        return result
    }

    fun colorIndex(name: String): Int = (name.hashCode() and Int.MAX_VALUE) % 6
}
