package moe.rinn.mychu

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AppUpdateChannel(context: Context, flutterEngine: FlutterEngine) {
    private val engine = AppUpdateEngine(context.applicationContext)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mychu/app_update")
    @Volatile private var disposed = false
    @Volatile private var taskId: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method !in setOf("inspect", "merge", "verifyFull", "finish")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            scope.launch {
                try {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val value = when (call.method) {
                        "inspect" -> engine.inspect().also { taskId = it["taskId"] as String }
                        "merge" -> engine.merge(args)
                        "verifyFull" -> engine.verifyFull(args)
                        else -> { engine.finish(args); taskId = null; null }
                    }
                    withContext(Dispatchers.Main.immediate) {
                        if (!disposed) result.success(value)
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    withContext(Dispatchers.Main.immediate) {
                        if (!disposed) result.error(
                            (error as? AppUpdateEngine.Failure)?.code ?: "UPDATE_FAILED",
                            "安装包处理失败", null,
                        )
                    }
                } finally {
                    // JNI may finish after Activity destruction. Clean only after it returns.
                    if (disposed) taskId?.let {
                        engine.finish(mapOf("taskId" to it, "retainApk" to false))
                        taskId = null
                    }
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        scope.cancel()
        // A queued operation that never started still has a workspace to release.
        val id = taskId
        if (id != null) {
            CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
                engine.finish(mapOf("taskId" to id, "retainApk" to false))
            }
        }
    }
}
