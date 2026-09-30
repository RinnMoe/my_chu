package moe.rinn.mychu.desktopwidgets

import android.content.Context
import android.content.Intent
import android.app.AlarmManager
import android.app.PendingIntent
import android.os.Build
import java.time.Instant
import java.time.ZoneOffset
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.GlanceTheme
import androidx.glance.background
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.components.Scaffold
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import moe.rinn.mychu.MainActivity
import moe.rinn.mychu.R
import org.json.JSONObject

internal class TodayScheduleWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 110.dp),
            DpSize(180.dp, 110.dp),
            DpSize(300.dp, 110.dp),
            DpSize(300.dp, 160.dp),
            DpSize(300.dp, 220.dp),
        ),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val now = Instant.now()
        val data = withContext(Dispatchers.IO) {
            WidgetSnapshotStore(context.applicationContext).readToday(now)
        }
        try {
            scheduleNextRefresh(context.applicationContext, data, now)
        } catch (_: RuntimeException) {
            // Alarm scheduling is best-effort; the widget can still render cached courses.
        }
        provideContent {
            TodayScheduleContent(data)
        }
    }
}

internal class TodayScheduleWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TodayScheduleWidget()
}

private fun scheduleNextRefresh(
    context: Context,
    data: TodayScheduleWidgetData,
    now: Instant,
) {
    val alarmManager = context.getSystemService(AlarmManager::class.java)
    val intent = Intent(context, DesktopWidgetRefreshReceiver::class.java)
        .setAction(DesktopWidgetRefreshReceiver.ACTION_REFRESH)
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    val operation = PendingIntent.getBroadcast(context, 460201, intent, flags)
    alarmManager.cancel(operation)
    if (data.status != TodayScheduleStatus.READY) return

    val midnight = data.businessDate.plusDays(1).atStartOfDay().toInstant(ZoneOffset.ofHours(8))
    val nextEnd = data.courses.mapNotNull { it.endAt }
        .filter { it.isAfter(now) }
        .minOrNull()
    val nextRefresh = minOf(midnight, nextEnd ?: midnight)
    if (!nextRefresh.isAfter(now)) return
    val canScheduleExactly = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        alarmManager.canScheduleExactAlarms()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && canScheduleExactly) {
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            nextRefresh.toEpochMilli(),
            operation,
        )
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            nextRefresh.toEpochMilli(),
            operation,
        )
    } else {
        alarmManager.set(AlarmManager.RTC_WAKEUP, nextRefresh.toEpochMilli(), operation)
    }
}

@androidx.compose.runtime.Composable
private fun TodayScheduleContent(data: TodayScheduleWidgetData) {
    val context = LocalContext.current
    val scheduleRequest = JSONObject()
        .put("schemaVersion", 1)
        .put("targetId", "feature.academic.schedule")
        .toString()
    val openSchedule = Intent(context, MainActivity::class.java).apply {
        action = MainActivity.ACTION_OPEN_WIDGET_TARGET
        setData(android.net.Uri.parse("mychu-widget://shortcut/feature.academic.schedule"))
        putExtra(MainActivity.EXTRA_WIDGET_LAUNCH_REQUEST, scheduleRequest)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    val compact = LocalSize.current.width < 180.dp
    val scheduleClick = actionStartActivity(openSchedule, actionParametersOf())

    GlanceTheme {
        Scaffold(
            modifier = GlanceModifier.fillMaxSize(),
            backgroundColor = GlanceTheme.colors.widgetBackground,
            horizontalPadding = if (compact) 10.dp else 16.dp,
        ) {
            if (data.status == TodayScheduleStatus.READY && data.courses.isEmpty()) {
                Box(
                    modifier = GlanceModifier.fillMaxSize().clickable(scheduleClick),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "今天没有课了~",
                        style = TextStyle(
                            color = GlanceTheme.colors.onSurfaceVariant,
                            fontSize = if (compact) 13.sp else 16.sp,
                        ),
                        maxLines = 1,
                    )
                }
            } else {
                Column(
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .clickable(scheduleClick)
                        .padding(vertical = 5.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Row(
                        modifier = GlanceModifier
                            .fillMaxWidth()
                            .clickable(scheduleClick),
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        Text(
                            text = data.currentWeek?.let { "第${it}周" } ?: "第—周",
                            modifier = GlanceModifier.defaultWeight(),
                            style = TextStyle(
                                color = GlanceTheme.colors.onSurface,
                                fontSize = if (compact) 12.sp else 14.sp,
                                fontWeight = FontWeight.Bold,
                            ),
                            maxLines = 1,
                        )
                        if (data.status == TodayScheduleStatus.READY) {
                            Text(
                                text = "${data.courses.size}节课",
                                style = TextStyle(
                                    color = GlanceTheme.colors.secondary,
                                    fontSize = if (compact) 11.sp else 12.sp,
                                ),
                                maxLines = 1,
                            )
                        }
                    }
                    Spacer(GlanceModifier.height(if (compact) 6.dp else 8.dp))
                    when (data.status) {
                        TodayScheduleStatus.SIGNED_OUT ->
                            EmptyMessage("登录后显示今日课表", compact, openSchedule)
                        TodayScheduleStatus.NO_SCHEDULE ->
                            EmptyMessage("暂无课表，打开 MyCHU 获取", compact, openSchedule)
                        TodayScheduleStatus.CALENDAR_UNAVAILABLE ->
                            EmptyMessage("课表日期信息暂不可用", compact, openSchedule)
                        TodayScheduleStatus.UNAVAILABLE ->
                            EmptyMessage("打开 MyCHU 同步今日课表", compact, openSchedule)
                        TodayScheduleStatus.READY -> {
                            LazyColumn(
                                modifier = GlanceModifier
                                    .fillMaxWidth()
                                    .defaultWeight(),
                            ) {
                                items(
                                    items = data.courses,
                                    itemId = { course ->
                                        listOf(
                                            course.courseName,
                                            course.location,
                                            course.startPeriod,
                                            course.endPeriod,
                                        ).joinToString("|").hashCode().toLong()
                                    },
                                ) { course ->
                                    CourseRow(course, compact, openSchedule)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun CourseRow(
    course: TodayScheduleCourse,
    compact: Boolean,
    openSchedule: Intent,
) {
    val metadataStyle = TextStyle(
        color = GlanceTheme.colors.onSurfaceVariant,
        fontSize = if (compact) 10.sp else 11.sp,
    )
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(48.dp)
            .clickable(actionStartActivity(openSchedule, actionParametersOf())),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(
            modifier = GlanceModifier
                .width(3.dp)
                .height(36.dp)
                .background(GlanceTheme.colors.primary)
                .cornerRadius(2.dp),
        )
        Column(
            modifier = GlanceModifier
                .defaultWeight()
                .padding(start = if (compact) 8.dp else 10.dp),
        ) {
            Text(
                text = course.courseName,
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontSize = if (compact) 12.sp else 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                if (course.location.isNotBlank()) {
                    Text(
                        text = course.location,
                        modifier = GlanceModifier.defaultWeight(),
                        style = metadataStyle,
                        maxLines = 1,
                    )
                    Spacer(GlanceModifier.width(4.dp))
                }
                Text(
                    text = course.displayTime,
                    style = metadataStyle,
                    maxLines = 1,
                )
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun EmptyMessage(
    message: String,
    compact: Boolean,
    openSchedule: Intent,
) {
    Text(
        text = message,
        modifier = GlanceModifier
            .fillMaxWidth()
            .clickable(actionStartActivity(openSchedule, actionParametersOf())),
        style = TextStyle(
            color = GlanceTheme.colors.onSurfaceVariant,
            fontSize = if (compact) 12.sp else 14.sp,
        ),
        maxLines = 2,
    )
}
