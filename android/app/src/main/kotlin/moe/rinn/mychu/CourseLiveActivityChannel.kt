package moe.rinn.mychu

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import moe.rinn.mychu.courselive.CourseLiveEngine
import moe.rinn.mychu.courselive.CourseLiveDeveloperTest
import org.json.JSONObject

/**
 * Host channel for the pre-class course activity.
 *
 * The shared layer owns course projection, the switch and the account boundary;
 * this channel only validates ownership, persists the minimal plan and applies
 * the local effects. No method performs campus networking.
 */
class CourseLiveActivityChannel(
    private val context: Context,
    flutterEngine: FlutterEngine,
) {
    private val channel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "mychu/course_live_activity",
    )

    init {
        if (BuildConfig.DEBUG) CourseLiveDeveloperTest.stop(context)
        channel.setMethodCallHandler { call, result ->
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                if (BuildConfig.DEBUG && call.method in setOf("activate", "deactivate", "replacePlan", "clearPlan")) {
                    CourseLiveDeveloperTest.stop(context, reschedule = false)
                }
                when (call.method) {
                    "startDeveloperTest" -> {
                        if (!BuildConfig.DEBUG) result.notImplemented()
                        else result.success(CourseLiveDeveloperTest.start(
                            context, args["delayed"] == true, args["ongoing"] == true,
                        ))
                    }
                    "stopDeveloperTest" -> {
                        if (!BuildConfig.DEBUG) result.notImplemented()
                        else { CourseLiveDeveloperTest.stop(context); result.success(null) }
                    }
                    "status" -> result.success(CourseLiveEngine.status(context))
                    // Lets the shared layer tell a re-attach from a lineage
                    // change: the same owner keeps its plan and dismissal
                    // ledger across a process restart.
                    "activatedOwner" -> result.success(CourseLiveEngine.activatedOwner(context))
                    // The persisted plan, so a partial projection after a process
                    // restart can merge against it instead of replacing it.
                    "plannedPayload" -> result.success(CourseLiveEngine.plannedPayload(context))
                    "activate" -> {
                        val owner = args["owner"] as? String
                        if (owner.isNullOrBlank()) {
                            result.error("INVALID_OWNER", "课程实时动态归属无效", null)
                        } else {
                            result.success(CourseLiveEngine.activate(context, owner))
                        }
                    }
                    "deactivate" -> {
                        CourseLiveEngine.deactivate(context)
                        result.success(null)
                    }
                    "replacePlan" -> {
                        val owner = args["owner"] as? String
                        val generation = (args["generation"] as? Number)?.toLong()
                        if (owner.isNullOrBlank() || generation == null) {
                            result.error("INVALID_PLAN", "课程实时动态计划无效", null)
                        } else {
                            CourseLiveEngine.replacePlan(
                                context,
                                owner,
                                generation,
                                JSONObject(args),
                            )
                            result.success(null)
                        }
                    }
                    "clearPlan" -> {
                        val owner = args["owner"] as? String
                        val generation = (args["generation"] as? Number)?.toLong()
                        if (owner.isNullOrBlank() || generation == null) {
                            result.error("INVALID_PLAN", "课程实时动态计划无效", null)
                        } else {
                            CourseLiveEngine.clearPlan(context, owner, generation)
                            result.success(null)
                        }
                    }
                    "reschedule" -> {
                        CourseLiveEngine.reschedule(context)
                        result.success(null)
                    }
                    "validateLaunch" -> {
                        val owner = args["owner"] as? String
                        val eventId = args["eventId"] as? String
                        val generation = (args["generation"] as? Number)?.toLong() ?: -1L
                        result.success(
                            CourseLiveEngine.validateLaunch(
                                context,
                                owner,
                                generation,
                                eventId,
                                System.currentTimeMillis(),
                            ),
                        )
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("COURSE_LIVE_FAILED", "课程实时动态操作失败", null)
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
