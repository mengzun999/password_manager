package com.meng.password_manager

import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import io.flutter.embedding.android.FlutterFragmentActivity  // ✅ 改这里
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {  // ✅ 改这里
    private val CHANNEL = "com.meng.passwordmanager/apps"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    getInstalledApps(result)
                }
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        getAppIcon(packageName, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "packageName is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getInstalledApps(result: MethodChannel.Result) {
        try {
            val packageManager = packageManager
            val apps = mutableListOf<Map<String, Any?>>()

            val packages = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)

            for (pkg in packages) {
                val packageName = pkg.packageName
                // 跳过系统应用
                if (isSystemApp(packageName)) continue

                try {
                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                    val appName = packageManager.getApplicationLabel(appInfo).toString()
                    val iconBytes = getAppIconBytes(packageName)

                    apps.add(mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "iconBytes" to iconBytes
                    ))
                } catch (e: Exception) {
                    // 跳过无法获取信息的应用
                    continue
                }
            }

            if (apps.isEmpty()) {
                result.error("NO_APPS", "没有找到已安装的应用", null)
                return
            }

            // 按应用名称排序
            val sortedApps = apps.sortedBy { it["appName"] as String }
            result.success(sortedApps)

        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun getAppIcon(packageName: String, result: MethodChannel.Result) {
        try {
            val iconBytes = getAppIconBytes(packageName)
            if (iconBytes != null) {
                result.success(iconBytes)
            } else {
                result.error("NO_ICON", "无法获取应用图标", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val packageManager = packageManager
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = drawableToBitmap(drawable)

            val scaledBitmap = Bitmap.createScaledBitmap(bitmap, 48, 48, true)

            val stream = ByteArrayOutputStream()
            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            scaledBitmap.recycle()
            bitmap.recycle()
            stream.toByteArray()
        } catch (e: Exception) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 48
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 48
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun isSystemApp(packageName: String): Boolean {
        val systemPrefixes = listOf(
            "android",
            "com.android",
            "com.google.android",
            "com.google.android.gms",
            "com.google.android.apps"
        )
        return systemPrefixes.any { packageName.startsWith(it) }
    }
}