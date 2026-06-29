package com.sbox.sbox

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget 2×2 de pantalla de inicio: muestra el estado de conexión y el último
 * contenido recibido. Los datos los empuja la app Flutter con `home_widget`.
 * Tocarlo abre sbox.
 */
class SboxWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.sbox_widget)

            val connected = widgetData.getBoolean("connected", false)
            val status = widgetData.getString("status", "Desconectado") ?: "Desconectado"
            val last = widgetData.getString("lastText", "") ?: ""

            views.setTextViewText(R.id.widget_status, status)
            views.setTextColor(
                R.id.widget_status,
                if (connected) 0xFF34D399.toInt() else 0xFF8A8F98.toInt(),
            )
            views.setTextViewText(
                R.id.widget_last,
                if (last.isEmpty()) "Sin contenido todavía" else last,
            )

            // Tocar cualquier parte del widget abre la app.
            val intent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.widget_root, intent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
