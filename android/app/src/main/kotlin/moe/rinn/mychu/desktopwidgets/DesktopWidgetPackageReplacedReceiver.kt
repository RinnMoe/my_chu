package moe.rinn.mychu.desktopwidgets

import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.MyPackageReplacedReceiver

internal class DesktopWidgetPackageReplacedReceiver : MyPackageReplacedReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        super.onReceive(context, intent)
        if (context != null && intent?.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            context.sendBroadcast(
                Intent(context, DesktopWidgetRefreshReceiver::class.java)
                    .setAction(DesktopWidgetRefreshReceiver.ACTION_REFRESH),
            )
        }
    }
}
