package com.github.qcxs.discuz

import android.app.Service
import android.content.Intent
import android.os.IBinder

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

    companion object {
        const val EXTRA_ENDPOINT = "endpoint"
    }
}
