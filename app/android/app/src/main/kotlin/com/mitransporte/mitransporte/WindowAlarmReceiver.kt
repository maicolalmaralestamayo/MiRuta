package com.mitransporte.mitransporte

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.mitransporte.miruta_alarm.WindowAlarm
import com.pravera.flutter_foreground_task.service.ForegroundService
import com.pravera.flutter_foreground_task.service.ForegroundServiceManager
import org.json.JSONArray
import org.json.JSONObject

/**
 * Ventana de viaje (docs/11 §11.62). Al sonar la alarma exacta (X antes de la
 * salida) arranca el servicio de ubicación en primer plano aunque la app esté
 * cerrada, con las opciones que dejó la app (paquete miruta_alarm). Al
 * reiniciar el teléfono (o al actualizar la app) vuelve a programar la alarma;
 * si su hora ya pasó, la programa para dentro de un momento (desde el arranque
 * del teléfono Android no deja abrir un servicio de ubicación directamente).
 */
class WindowAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, "android.intent.action.QUICKBOOT_POWERON" -> {
                val at = WindowAlarm.at(context)
                if (at > 0) WindowAlarm.schedule(context, maxOf(at, System.currentTimeMillis() + 30_000))
            }
            else -> start(context)
        }
    }

    private fun start(context: Context) {
        if (ForegroundService.isRunningServiceState.value) return
        val payload = WindowAlarm.payload(context) ?: return
        try {
            @Suppress("UNCHECKED_CAST")
            val options = toValue(JSONObject(payload)) as Map<String, Any?>
            ForegroundServiceManager().start(context, options)
        } catch (e: Exception) {
            Log.e("MiRuta", "No se pudo abrir la ventana de viaje: ${e.message}")
        }
    }

    private fun toValue(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { toValue(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { toValue(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }
}
