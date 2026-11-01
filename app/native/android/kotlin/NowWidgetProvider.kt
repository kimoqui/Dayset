package com.dayset.dayset

// DaySet '지금' 위젯 (안드로이드)
//
// 버튼을 누르면 앱을 열지 않고 브로드캐스트로 공유 저장소에 탭 기록을 쌓는다.
// 저장소는 home_widget 패키지가 쓰는 "HomeWidgetPreferences"이고,
// 키와 형식은 lib/platform/widget_bridge.dart 와 같아야 한다.

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class NowWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = buildViews(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_TAP) return
        val activity = intent.getStringExtra(EXTRA_ACTIVITY) ?: return
        // 같은 상태를 다시 누르면 아무것도 하지 않는다(앱 규칙과 같음).
        if (SharedStore.current(context) != activity) {
            SharedStore.append(context, activity, System.currentTimeMillis())
        }
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, NowWidgetProvider::class.java))
        onUpdate(context, manager, ids)
    }

    companion object {
        const val ACTION_TAP = "com.dayset.dayset.NOW_TAP"
        const val EXTRA_ACTIVITY = "activity"

        private val buttons = listOf(
            R.id.btn_sleep to "sleep",
            R.id.btn_meal to "meal",
            R.id.btn_work to "work",
            R.id.btn_exercise to "exercise",
            R.id.btn_rest to "rest",
        )
        private val labels = mapOf(
            "sleep" to "수면", "meal" to "식사", "work" to "업무",
            "exercise" to "운동", "rest" to "휴식",
        )

        fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.now_widget)
            val current = SharedStore.current(context)
            views.setTextViewText(
                R.id.now_title,
                labels[current]?.let { "$it 중" } ?: "지금 무엇을 하나요?",
            )
            buttons.forEachIndexed { index, (viewId, name) ->
                val tap = Intent(context, NowWidgetProvider::class.java).apply {
                    action = ACTION_TAP
                    putExtra(EXTRA_ACTIVITY, name)
                }
                val pending = PendingIntent.getBroadcast(
                    context, index, tap,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(viewId, pending)
                val on = name == current
                views.setInt(
                    viewId, "setBackgroundResource",
                    if (on) R.drawable.now_btn_on else R.drawable.now_btn_off,
                )
                views.setTextColor(viewId, if (on) Color.WHITE else Color.parseColor("#1B1F1D"))
            }
            return views
        }
    }
}

object SharedStore {
    private const val PREFS = "HomeWidgetPreferences"
    private const val KEY_PENDING = "pending_events"
    private const val KEY_CURRENT = "current_activity"
    private const val KEY_SINCE = "current_since"

    fun append(context: Context, activity: String, atMillis: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = try {
            JSONArray(prefs.getString(KEY_PENDING, "[]") ?: "[]")
        } catch (e: Exception) {
            JSONArray()
        }
        val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US).format(Date(atMillis))
        list.put(JSONObject().put("activity", activity).put("at", stamp))
        while (list.length() > 50) list.remove(0)
        prefs.edit()
            .putString(KEY_PENDING, list.toString())
            .putString(KEY_CURRENT, activity)
            .putString(KEY_SINCE, stamp)
            .apply()
    }

    fun current(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_CURRENT, null)
            ?.takeIf { it.isNotEmpty() }
}
