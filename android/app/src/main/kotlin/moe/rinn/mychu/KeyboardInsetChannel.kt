package moe.rinn.mychu

import android.app.Activity
import android.os.Build
import android.view.View
import android.view.ViewTreeObserver
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.lang.ref.WeakReference
import kotlin.math.round

internal fun computeKeyboardOverlapDp(
    imeBottomPx: Int,
    decorHeightPx: Int,
    contentBottomPx: Int,
    navBottomPx: Int,
    density: Float,
): Double {
    if (imeBottomPx <= 0 || density <= 0f) return 0.0
    val contentBottomInsetPx = (decorHeightPx - contentBottomPx).coerceAtLeast(0)
    val webViewBottomInsetPx = maxOf(contentBottomInsetPx, navBottomPx.coerceAtLeast(0))
    val overlapPx = (imeBottomPx - webViewBottomInsetPx).coerceAtLeast(0)
    return overlapPx.toDouble() / density.toDouble()
}

/**
 * 实时转发 Android 软键盘（IME）动画期间的底部遮挡高度（dp）到 Flutter 侧，
 * 以便内嵌 WebView 逐帧同步布局而无需每帧重建原生视图尺寸。
 */
class KeyboardInsetChannel(
    activity: Activity,
    flutterEngine: FlutterEngine,
) : EventChannel.StreamHandler {
    private val activityRef = WeakReference(activity)
    private val channel = EventChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "mychu/keyboard_insets",
    ).also {
        it.setStreamHandler(this)
    }

    private var eventSink: EventChannel.EventSink? = null
    private var previousSoftInputMode: Int? = null
    private var globalLayoutListener: ViewTreeObserver.OnGlobalLayoutListener? = null
    private var activeImeAnimations = 0
    private var lastSentInset = Double.NaN
    private var lastSentAnimating: Boolean? = null
    private var disposed = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        detach()
        if (disposed) return
        eventSink = events
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            events?.success(
                mapOf(
                    "supported" to false,
                    "inset" to 0.0,
                    "animating" to false,
                ),
            )
            return
        }
        attachApi30()
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun attachApi30() {
        val activity = activityRef.get() ?: return
        val window = activity.window ?: return
        val decorView = window.decorView

        val prev = window.attributes.softInputMode
        previousSoftInputMode = prev
        @Suppress("DEPRECATION")
        val resizeMode =
            (prev and WindowManager.LayoutParams.SOFT_INPUT_MASK_ADJUST.inv()) or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        window.setSoftInputMode(resizeMode)

        decorView.setWindowInsetsAnimationCallback(
            object : WindowInsetsAnimation.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
                override fun onStart(
                    animation: WindowInsetsAnimation,
                    bounds: WindowInsetsAnimation.Bounds,
                ): WindowInsetsAnimation.Bounds {
                    if (animation.typeMask and WindowInsets.Type.ime() != 0) {
                        activeImeAnimations++
                    }
                    return super.onStart(animation, bounds)
                }

                override fun onProgress(
                    insets: WindowInsets,
                    runningAnimations: MutableList<WindowInsetsAnimation>,
                ): WindowInsets {
                    val hasImeAnimation =
                        activeImeAnimations > 0 ||
                            runningAnimations.any { it.typeMask and WindowInsets.Type.ime() != 0 }
                    if (hasImeAnimation) {
                        emitInset(computeOverlap(activity, insets), animating = true)
                    }
                    return insets
                }

                override fun onEnd(animation: WindowInsetsAnimation) {
                    if (animation.typeMask and WindowInsets.Type.ime() != 0) {
                        activeImeAnimations = (activeImeAnimations - 1).coerceAtLeast(0)
                        val rootInsets = decorView.rootWindowInsets
                        emitInset(
                            computeOverlap(activity, rootInsets),
                            animating = activeImeAnimations > 0,
                            force = activeImeAnimations == 0,
                        )
                    }
                }
            },
        )

        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            if (activeImeAnimations == 0) {
                val currentActivity = activityRef.get() ?: return@OnGlobalLayoutListener
                val rootInsets = currentActivity.window?.decorView?.rootWindowInsets
                emitInset(computeOverlap(currentActivity, rootInsets), animating = false)
            }
        }
        globalLayoutListener = listener
        decorView.viewTreeObserver.addOnGlobalLayoutListener(listener)

        emitInset(computeOverlap(activity, decorView.rootWindowInsets), animating = false, force = true)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun computeOverlap(activity: Activity, insets: WindowInsets?): Double {
        if (insets == null) return 0.0
        val decorView = activity.window?.decorView ?: return 0.0
        val contentView = activity.findViewById<View>(android.R.id.content) ?: return 0.0
        val loc = IntArray(2)
        contentView.getLocationInWindow(loc)
        val contentBottomPx = loc[1] + contentView.height
        return computeKeyboardOverlapDp(
            imeBottomPx = insets.getInsets(WindowInsets.Type.ime()).bottom,
            decorHeightPx = decorView.height,
            contentBottomPx = contentBottomPx,
            navBottomPx = insets.getInsets(WindowInsets.Type.navigationBars()).bottom,
            density = activity.resources.displayMetrics.density,
        )
    }

    private fun emitInset(insetDp: Double, animating: Boolean, force: Boolean = false) {
        val rounded = round(insetDp * 10.0) / 10.0
        if (!force && rounded == lastSentInset && animating == lastSentAnimating) {
            return
        }
        lastSentInset = rounded
        lastSentAnimating = animating
        eventSink?.success(
            mapOf(
                "supported" to true,
                "inset" to rounded,
                "animating" to animating,
            ),
        )
    }

    override fun onCancel(arguments: Any?) {
        detach()
    }

    private fun detach() {
        eventSink = null
        activeImeAnimations = 0
        lastSentInset = Double.NaN
        lastSentAnimating = null
        val activity = activityRef.get()
        if (activity != null) {
            val window = activity.window
            val decorView = window?.decorView
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                decorView?.setWindowInsetsAnimationCallback(null)
            }
            val listener = globalLayoutListener
            if (listener != null && decorView != null && decorView.viewTreeObserver.isAlive) {
                decorView.viewTreeObserver.removeOnGlobalLayoutListener(listener)
            }
            val savedMode = previousSoftInputMode
            if (savedMode != null) {
                window?.setSoftInputMode(savedMode)
            }
        }
        globalLayoutListener = null
        previousSoftInputMode = null
    }

    fun dispose() {
        disposed = true
        detach()
        channel.setStreamHandler(null)
    }
}
