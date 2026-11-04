package com.github.qcxs.discuz

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * MCP 运行状态前台服务。
 *
 * 只做一件事：持有那条常驻通知，让系统与用户都知道"应用正在运行 MCP 服务"。
 * 它**不持有** MCP 的监听端口——HTTP 服务在 Flutter 侧进程内，服务只是状态载体。
 *
 * 应用被划掉 → 进程结束 → 服务销毁 → 通知自动消失，
 * 不会留下"服务已开启"的假状态（普通通知做不到这点）。
 */
class McpForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val endpoint = intent?.getStringExtra(EXTRA_ENDPOINT).orEmpty()
        startForeground(
            McpStatusNotification.NOTIFICATION_ID,
            McpStatusNotification.buildNotification(this, endpoint),
        )
        return START_NOT_STICKY
    }

    /**
     * Android 15+ 对 dataSync 类型前台服务有 6 小时/24 小时配额。
     * 配额用尽时系统回调这里；必须主动停止服务，否则会被判定为 ANR/异常。
     * 停止后状态通知消失，但 MCP HTTP 服务仍在 Flutter 进程内运行（进程未死）。
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w("MTBBS_MCP", "前台服务超时（type=$fgsType），停止状态通知")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf(startId)
    }

    companion object {
        const val EXTRA_ENDPOINT = "endpoint"
    }
}
