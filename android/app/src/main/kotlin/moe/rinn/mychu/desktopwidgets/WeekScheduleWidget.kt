package moe.rinn.mychu.desktopwidgets

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.*
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import moe.rinn.mychu.R
import moe.rinn.mychu.MainActivity

internal class WeekScheduleWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val now = Instant.now()
        val data = withContext(Dispatchers.IO) { WidgetSnapshotStore(context).readWeek(now) }
        runCatching { DesktopWidgetScheduler.schedule(context.applicationContext, now) }
        provideContent { GlanceTheme { WeekScheduleContent(data) } }
    }
}

internal class WeekScheduleWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WeekScheduleWidget()
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        runCatching { DesktopWidgetScheduler.schedule(context.applicationContext) }
    }
}

private val courseColors = listOf(
    ColorProvider(R.color.widget_course_0), ColorProvider(R.color.widget_course_1),
    ColorProvider(R.color.widget_course_2), ColorProvider(R.color.widget_course_3),
    ColorProvider(R.color.widget_course_4), ColorProvider(R.color.widget_course_5),
)
private val courseText = ColorProvider(R.color.widget_course_text)

@Composable
private fun WeekScheduleContent(data: WeekScheduleWidgetData) {
    val context = LocalContext.current
    val open = Intent(context, MainActivity::class.java).apply {
        action = MainActivity.ACTION_OPEN_WIDGET_TARGET
        setData(Uri.parse("mychu-widget://shortcut/feature.academic.schedule"))
        putExtra(MainActivity.EXTRA_WIDGET_LAUNCH_REQUEST, """{"schemaVersion":1,"targetId":"feature.academic.schedule"}""")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    val size = LocalSize.current
    val periodHeight = ((size.height.value - 86f) / 11f).coerceAtLeast(12f)
    Column(
        modifier = GlanceModifier.fillMaxSize().background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(20.dp).clickable(actionStartActivity(open)).padding(10.dp),
    ) {
        Row(modifier = GlanceModifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("周课表", modifier = GlanceModifier.defaultWeight(), style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 14.sp, fontWeight = FontWeight.Bold))
            Text(data.currentWeek?.let { "第${it}周" } ?: "", style = TextStyle(color = GlanceTheme.colors.primary, fontSize = 12.sp))
        }
        Text("${dateLabel(data.weekStart)}—${dateLabel(data.weekStart.plusDays(6))}",
            modifier = GlanceModifier.height(18.dp), style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp))
        if (data.status != WeekScheduleStatus.READY || data.days.all { it.isEmpty() }) {
            Box(modifier = GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(statusMessage(data), style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 14.sp), maxLines = 2)
            }
        } else {
            Row(modifier = GlanceModifier.fillMaxWidth().height(16.dp)) {
                Spacer(GlanceModifier.width(18.dp))
                for (day in 0..6) {
                    val date = data.weekStart.plusDays(day.toLong())
                    Box(modifier = GlanceModifier.defaultWeight(), contentAlignment = Alignment.Center) {
                        Text("${listOf("一", "二", "三", "四", "五", "六", "日")[day]} ${date.dayOfMonth}",
                            style = TextStyle(color = if (date == data.businessDate) GlanceTheme.colors.primary else GlanceTheme.colors.onSurfaceVariant,
                                fontWeight = if (date == data.businessDate) FontWeight.Bold else FontWeight.Normal, fontSize = 10.sp), maxLines = 1)
                    }
                }
            }
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                Column(modifier = GlanceModifier.width(18.dp)) {
                    for (period in 1..11) {
                        Box(modifier = GlanceModifier.height(periodHeight.dp), contentAlignment = Alignment.Center) {
                            Text("$period", style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp))
                        }
                        if (period == 4 || period == 8) Spacer(GlanceModifier.height(4.dp))
                    }
                }
                for (blocks in data.days) {
                    Column(modifier = GlanceModifier.defaultWeight().padding(horizontal = 1.dp)) {
                        var nextPeriod = 1
                        for (block in blocks) {
                            for (period in nextPeriod until block.startPeriod) {
                                Spacer(GlanceModifier.height(periodHeight.dp))
                                if (period == 4 || period == 8) Spacer(GlanceModifier.height(4.dp))
                            }
                            val gaps = listOf(4, 8).count { it >= block.startPeriod && it < block.endPeriod }
                            val height = (block.endPeriod - block.startPeriod + 1) * periodHeight + gaps * 4f
                            CourseBlock(block, height, size.width.value)
                            if (block.endPeriod == 4 || block.endPeriod == 8) Spacer(GlanceModifier.height(4.dp))
                            nextPeriod = block.endPeriod + 1
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CourseBlock(block: WeekCourseBlock, height: Float, width: Float) {
    val course = block.courses.first()
    Column(
        modifier = GlanceModifier.fillMaxWidth().height(height.dp).padding(vertical = 1.dp)
            .background(courseColors[WeekScheduleSnapshotParser.colorIndex(course.courseName)])
            .cornerRadius(4.dp).padding(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(course.courseName, modifier = GlanceModifier.defaultWeight(),
                style = TextStyle(color = courseText, fontSize = 10.sp, fontWeight = FontWeight.Medium), maxLines = if (height >= 32) 2 else 1)
            if (block.courses.size > 1) {
                Text("＋${block.courses.size - 1}", style = TextStyle(color = courseText, fontSize = 9.sp), maxLines = 1)
            }
        }
        if (height >= 52 && width >= 340 && course.location.isNotBlank()) {
            Text(course.location, style = TextStyle(color = courseText, fontSize = 9.sp), maxLines = 1)
        }
    }
}

private fun dateLabel(date: java.time.LocalDate) = "${date.monthValue}/${date.dayOfMonth}"

private fun statusMessage(data: WeekScheduleWidgetData) = when (data.status) {
    WeekScheduleStatus.SIGNED_OUT -> "登录后显示周课表"
    WeekScheduleStatus.NO_SCHEDULE -> "暂无课表，打开 MyCHU 获取"
    WeekScheduleStatus.CALENDAR_UNAVAILABLE -> "课表日期信息暂不可用"
    WeekScheduleStatus.UNAVAILABLE -> "打开 MyCHU 同步周课表"
    WeekScheduleStatus.OUTSIDE_TERM -> "当前不在教学周"
    WeekScheduleStatus.READY -> "本周暂无课程"
}
