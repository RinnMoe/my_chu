package moe.rinn.mychu

import android.app.Application
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.SharedPreferences
import android.os.Build
import android.widget.RemoteViews
import androidx.work.Configuration
import androidx.work.WorkManager
import moe.rinn.mychu.desktopwidgets.TodayScheduleWidgetReceiver

class MyChuApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // WorkManager's startup initializer skips non-default app processes.
        // Glance's RemoteWorkerService runs in :widgetProvider, so initialize
        // WorkManager there before the service handles a widget update.
        if (!WorkManager.isInitialized()) {
            WorkManager.initialize(this, Configuration.Builder().build())
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
                Application.getProcessName() == packageName
        ) {
            publishWidgetPreviews()
        }
    }

    private fun publishWidgetPreviews() {
        val preferences = getSharedPreferences(PREVIEW_PREFERENCES, MODE_PRIVATE)
        val widgetManager = AppWidgetManager.getInstance(this)

        publishWidgetPreviewOnce(
            preferences,
            widgetManager,
            TODAY_SCHEDULE_PREVIEW_ATTEMPTED,
            TodayScheduleWidgetReceiver::class.java,
            R.layout.today_schedule_widget_preview,
        )
    }

    private fun publishWidgetPreviewOnce(
        preferences: SharedPreferences,
        widgetManager: AppWidgetManager,
        attemptKey: String,
        receiver: Class<*>,
        layout: Int,
    ) {
        if (preferences.getBoolean(attemptKey, false)) return

        val published = runCatching {
            widgetManager.setWidgetPreview(
                ComponentName(this, receiver),
                AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN,
                RemoteViews(packageName, layout),
            )
        }.getOrDefault(false)
        if (published) preferences.edit().putBoolean(attemptKey, true).apply()
    }

    private companion object {
        const val PREVIEW_PREFERENCES = "desktop_widget_previews"
        const val TODAY_SCHEDULE_PREVIEW_ATTEMPTED = "today_schedule_published_v6"
    }
}
