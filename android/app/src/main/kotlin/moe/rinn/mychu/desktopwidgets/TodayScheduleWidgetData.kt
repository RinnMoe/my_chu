package moe.rinn.mychu.desktopwidgets

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

internal enum class TodayScheduleStatus {
    SIGNED_OUT,
    NO_SCHEDULE,
    CALENDAR_UNAVAILABLE,
    READY,
    UNAVAILABLE,
}

internal data class TodayScheduleCourse(
    val courseName: String,
    val location: String,
    val displayTime: String,
    val startPeriod: Int,
    val endPeriod: Int,
    val endAt: Instant?,
    val startAt: Instant? = null,
)

internal data class TodayScheduleWidgetData(
    val businessDate: LocalDate,
    val status: TodayScheduleStatus,
    val courses: List<TodayScheduleCourse> = emptyList(),
    val currentWeek: Int? = null,
    val sourceLabel: String? = null,
)

internal object TodayScheduleSnapshotParser {
    private val east8 = ZoneOffset.ofHours(8)
    private val datePattern = Regex("^\\d{4}-\\d{2}-\\d{2}$")
    private val timePattern = Regex("^\\d{2}:\\d{2}$")

    fun businessDate(now: Instant = Instant.now()): LocalDate =
        now.atOffset(east8).toLocalDate()

    fun parseForNow(source: String, now: Instant = Instant.now()): TodayScheduleWidgetData =
        parse(source, businessDate(now), now)

    fun parse(
        source: String,
        businessDate: LocalDate,
        now: Instant? = null,
        academicOnly: Boolean = false,
    ): TodayScheduleWidgetData {
        val root = JSONObject(source)
        if (root.optInt("schemaVersion", -1) != 1 ||
            root.optInt("timezoneOffsetMinutes", -1) != 480
        ) {
            throw JSONException("Unsupported desktop widget snapshot")
        }
        val schedule = root.optJSONObject("schedule")
            ?: throw JSONException("Missing schedule")
        if (!academicOnly && schedule.optString("status") != "signedOut") {
            parseRecent(root, businessDate, now)?.let { return it }
        }
        val status = when (schedule.optString("status")) {
            "signedOut" -> TodayScheduleStatus.SIGNED_OUT
            "noSchedule" -> TodayScheduleStatus.NO_SCHEDULE
            "calendarUnavailable" -> TodayScheduleStatus.CALENDAR_UNAVAILABLE
            "ready" -> TodayScheduleStatus.READY
            else -> throw JSONException("Invalid schedule status")
        }
        if (status != TodayScheduleStatus.READY) {
            return TodayScheduleWidgetData(businessDate, status)
        }
        if (schedule.optString("semesterId").isBlank()) {
            throw JSONException("Missing semester ID")
        }
        val currentWeek = if (!schedule.has("currentWeek") ||
            schedule.isNull("currentWeek")
        ) {
            null
        } else {
            schedule.optInt("currentWeek", -1).takeIf { it > 0 }
                ?: throw JSONException("Invalid current week")
        }

        val occurrences = schedule.optJSONArray("occurrences")
            ?: throw JSONException("Missing occurrences")
        val courses = ArrayList<TodayScheduleCourse>()
        for (index in 0 until occurrences.length()) {
            val occurrence = occurrences.optJSONObject(index)
                ?: throw JSONException("Invalid occurrence")
            val dateText = occurrence.optString("date")
            if (!datePattern.matches(dateText)) {
                throw JSONException("Invalid occurrence date")
            }
            val date = try {
                LocalDate.parse(dateText)
            } catch (_: RuntimeException) {
                throw JSONException("Invalid occurrence date")
            }
            if (date != businessDate) continue

            val name = occurrence.optString("courseName").trim()
            if (name.isEmpty()) throw JSONException("Missing course name")
            val startPeriod = occurrence.optInt("startPeriod", -1)
            val endPeriod = occurrence.optInt("endPeriod", -1)
            if (startPeriod < 1 || endPeriod < startPeriod) {
                throw JSONException("Invalid course periods")
            }
            val startTime = occurrence.optString("startTime").takeIf {
                it.isNotEmpty() && timePattern.matches(it)
            }
            val endTime = occurrence.optString("endTime").takeIf {
                it.isNotEmpty() && timePattern.matches(it)
            }
            val endAt = endTime?.let {
                try {
                    date.atTime(LocalTime.parse(it)).toInstant(east8)
                } catch (_: RuntimeException) {
                    null
                }
            }
            if (now != null && endAt != null && !endAt.isAfter(now)) continue
            val fallbackLabel = occurrence.optString("periodLabel")
                .ifBlank { periodLabel(startPeriod, endPeriod) }
            courses.add(
                TodayScheduleCourse(
                    courseName = name,
                    location = occurrence.optString("location").trim(),
                    displayTime = if (startTime != null && endTime != null) {
                        "$startTime–$endTime"
                    } else {
                        fallbackLabel
                    },
                    startPeriod = startPeriod,
                    endPeriod = endPeriod,
                    endAt = endAt,
                ),
            )
        }
        courses.sortWith(
            compareBy<TodayScheduleCourse> { it.startPeriod }
                .thenBy { it.endPeriod }
                .thenBy { it.courseName },
        )
        return TodayScheduleWidgetData(
            businessDate,
            status,
            courses,
            currentWeek,
            if (!academicOnly && root.has("recentSchedule")) "课程可能未反映调休，打开更新" else null,
        )
    }

    private fun parseRecent(root: JSONObject, date: LocalDate, now: Instant?): TodayScheduleWidgetData? {
        val recent = root.optJSONObject("recentSchedule") ?: return null
        val first = LocalDate.parse(recent.getString("startDate"))
        val last = LocalDate.parse(recent.getString("endDate"))
        if (last != first.plusDays(6)) throw JSONException("Invalid recent range")
        if (date < first || date > last) return null
        val fetched = Instant.parse(recent.getString("fetchedAt"))
        val raw = recent.getJSONArray("courses")
        val courses = ArrayList<TodayScheduleCourse>()
        for (index in 0 until raw.length()) {
            val item = raw.getJSONObject(index)
            val start = Instant.parse(item.getString("start"))
            val end = Instant.parse(item.getString("end"))
            val day = start.atOffset(east8).toLocalDate()
            if (!end.isAfter(start) || day < first || day > last) throw JSONException("Invalid recent course time")
            val name = item.getString("name").trim()
            if (name.isEmpty() || item.getString("id").isBlank()) throw JSONException("Invalid recent course")
            if (day != date || (now != null && !end.isAfter(now))) continue
            courses.add(TodayScheduleCourse(
                courseName = name, location = item.getString("location"),
                displayTime = "${start.atOffset(east8).toLocalTime().toString().take(5)}–${end.atOffset(east8).toLocalTime().toString().take(5)}",
                startPeriod = item.optInt("startPeriod", 0),
                endPeriod = item.optInt("endPeriod", 0),
                startAt = start, endAt = end,
            ))
        }
        courses.sortBy { it.startAt }
        val fresh = recent.optBoolean("fresh", false) && fetched.atOffset(east8).toLocalDate() == date
        return TodayScheduleWidgetData(date, TodayScheduleStatus.READY, courses,
            sourceLabel = if (fresh) null else "课程待更新 · 打开更新")
    }

    private fun periodLabel(start: Int, end: Int): String =
        if (start == end) "第${start}节" else "第${start}–${end}节"
}
