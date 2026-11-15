package com.mitransporte.miruta_alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Alarma exacta de la ventana de viaje (docs/11 §11.62). Programa con
 * AlarmManager una alarma que entrega el intent a la clase
 * com.mitransporte.mitransporte.WindowAlarmReceiver de la app, que arranca el
 * servicio de ubicación (las alarmas exactas permiten arrancar un servicio en
 * primer plano desde segundo plano en Android 12+). Guarda la hora y los datos
 * para reprogramarla al reiniciar el teléfono.
 */
class MirutaAlarmPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "miruta_alarm").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", null, null)
        try {
            when (call.method) {
                "schedule" -> {
                    val at = (call.argument<Number>("at") ?: 0).toLong()
                    val payload = call.argument<String>("payload") ?: "{}"
                    WindowAlarm.save(ctx, at, payload)
                    WindowAlarm.schedule(ctx, at)
                    result.success(null)
                }
                "cancel" -> {
                    WindowAlarm.cancel(ctx)
                    result.success(null)
                }
                "scheduled" -> result.success(WindowAlarm.at(ctx))
                "canScheduleExact" -> result.success(WindowAlarm.canScheduleExact(ctx))
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + ctx.packageName))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        ctx.startActivity(intent)
                    }
                    result.success(null)
                }
                "manufacturer" -> result.success(Build.MANUFACTURER ?: "")
                "openBatterySettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + ctx.packageName))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    ctx.startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ALARM_ERROR", e.message, null)
        }
    }
}

/** Programación de la alarma (la usa también la app al reiniciar el teléfono). */
object WindowAlarm {
    private const val PREFS = "miruta_alarm"
    private const val KEY_AT = "at"
    private const val KEY_PAYLOAD = "payload"
    const val ACTION = "com.mitransporte.miruta_alarm.VENTANA"
    const val RECEIVER = "com.mitransporte.mitransporte.WindowAlarmReceiver"

    fun save(context: Context, at: Long, payload: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(KEY_AT, at).putString(KEY_PAYLOAD, payload).apply()
    }

    fun at(context: Context): Long = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_AT, 0L)

    fun payload(context: Context): String? = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PAYLOAD, null)

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return manager.canScheduleExactAlarms()
    }

    private fun pending(context: Context): PendingIntent {
        val intent = Intent(ACTION).setClassName(context.packageName, RECEIVER)
        return PendingIntent.getBroadcast(context, 7311, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun schedule(context: Context, at: Long) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val time = maxOf(at, System.currentTimeMillis() + 1000)
        val intent = pending(context)
        if (canScheduleExact(context)) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, intent)
        } else {
            // Sin permiso de alarmas exactas: aproximada (puede no arrancar el servicio).
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, intent)
        }
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.cancel(pending(context))
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }
}
