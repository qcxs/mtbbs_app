package com.github.qcxs.discuz

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * MCP 运行状态的前台服务通知。
 *
 * 用**前台服务**持有通知（而不是普通通知）：只有前台服务能保证
 * "应用在后台时通知依然常驻且代表真实状态"；应用被划掉时进程结束、
 * 服务随之销毁、通知自动消失，不会留下"服务已开启"的假状态。
 *
 * Android 13+ 需要 POST_NOTIFICATIONS：未授权时先发起一次系统请求，
 * 用户在系统弹窗里同意后由 [onPermissionResult] 补上；被拒则静默跳过
 * （不启动前台服务——通知看不见的前台服务没有意义，反而会占一个后台名额）。
 *
 * 刻意只用平台 API（不引 androidx），避免给构建增加依赖。
 */
object McpStatusNotification {
    private const val TAG = "MTBBS_MCP"

    const val CHANNEL = "mtbbs/mcp_status"
    const val PERMISSION_REQUEST_CODE = 8765
    const val NOTIFICATION_ID = 8765

    private const val CHANNEL_ID = "mtbbs_mcp_status"

    /** 等权限时暂存的通知内容（null 表示无需补发） */
    private var pendingEndpoint: String? = null

    /** 启动 / 更新前台服务通知 */
    fun start(context: Context, endpoint: String) {
        createChannel(context)
        if (!hasPermission(context)) {
            requestPermission(context)
            pendingEndpoint = endpoint
            return
        }
        pendingEndpoint = null
        startService(context, endpoint)
    }

    /** 停止前台服务（通知随之消失） */
    fun stop(context: Context) {
        pendingEndpoint = null
        context.stopService(Intent(context, McpForegroundService::class.java))
    }

    /** 由 MainActivity 在权限回调里调用 */
    fun onPermissionResult(context: Context, granted: Boolean) {
        val endpoint = pendingEndpoint ?: return
        pendingEndpoint = null
        if (granted) startService(context, endpoint)
    }

    /** 构建常驻通知（前台服务直接复用） */
    @Suppress("DEPRECATION")
    fun buildNotification(context: Context, endpoint: String): Notification {
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            pendingIntentFlags(),
        )
        // 有渠道用渠道构造器（O+），否则退回旧构造器
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_mcp)
            .setContentTitle("MCP 服务已开启")
            .setContentText(endpoint)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(contentIntent)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    private fun startService(context: Context, endpoint: String) {
        val intent = Intent(context, McpForegroundService::class.java)
            .putExtra(McpForegroundService.EXTRA_ENDPOINT, endpoint)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (e: Exception) {
            // Android 12+ 禁止从后台启动前台服务；MCP 由用户在前台开启，正常不会走到这里
            Log.w(TAG, "启动 MCP 前台服务失败: ${e.message}")
        }
    }

    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun notificationManager(context: Context): NotificationManager? =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager

    private fun hasPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val activity = context as? MainActivity ?: return
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST_CODE,
        )
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager(context) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "MCP 服务状态",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "MCP 服务开启时显示，便于确认服务正在运行"
                setShowBadge(false)
            },
        )
    }
}
