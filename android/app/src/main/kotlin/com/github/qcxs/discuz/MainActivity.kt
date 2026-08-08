package com.github.qcxs.discuz

import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Point
import android.graphics.Rect
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/// 折叠屏/自由窗口/分屏尺寸检测（参考 PiliPlus max_screen_size 机制）
///
/// - `getMaxScreenSize`：返回物理最大屏幕的逻辑尺寸 [width, height]（除以 density）。
///   折叠屏展开即整屏，用于判断当前窗口是否处于分屏/自由窗口/折叠小窗形态。
/// - `maxScreenSizeChanged`：仅折叠屏设备（带铰链传感器）在配置变化时主动通知
///   Dart 侧刷新缓存；普通手机/平板无此开销。
class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mtbbs/max_screen_size",
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getMaxScreenSize" -> {
                    val size = getMaxScreenSize()
                    result.success(if (size == null) null else intArrayOf(size[0], size[1]))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // 仅折叠屏设备在折叠/展开/窗口形态变化时刷新尺寸缓存
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_HINGE_ANGLE)
        ) {
            channel.invokeMethod("maxScreenSizeChanged", null)
        }
    }

    /// 物理最大屏幕逻辑尺寸（宽, 高）；异常时返回 null
    private fun getMaxScreenSize(): IntArray? {
        return try {
            val bounds: Rect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Android 11+：最大窗口度量（折叠屏展开即整屏）
                windowManager.maximumWindowMetrics.bounds
            } else {
                @Suppress("DEPRECATION")
                val display = windowManager.defaultDisplay
                val realSize = Point()
                @Suppress("DEPRECATION")
                display.getRealSize(realSize)
                Rect(0, 0, realSize.x, realSize.y)
            }
            val density = resources.displayMetrics.density
            intArrayOf(
                (bounds.width() / density).roundToInt(),
                (bounds.height() / density).roundToInt(),
            )
        } catch (_: Exception) {
            null
        }
    }
}
