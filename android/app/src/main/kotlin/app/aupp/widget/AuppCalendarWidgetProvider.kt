package app.aupp.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import app.aupp.MainActivity
import app.aupp.R
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

/**
 * Fork: a plain month calendar for the home screen that marks, without
 * saying what, the days something is due: green while far, orange the day
 * before, red on the day (and overdue). Dart sends only the days
 * (`aupp_calendar_due`, HomeWidgetService.saveDueDays); the colors are
 * worked out here, so they change at midnight with the app closed. Drawn
 * as one bitmap at the widget's size: round marks at any shape.
 */
class AuppCalendarWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val due = (widgetData.getString(KEY_DUE, null) ?: "")
            .split(',')
            .mapNotNull { runCatching { LocalDate.parse(it) }.getOrNull() }
            .toSet()
        val background = backgroundColor(widgetData)
        for (id in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.aupp_calendar_widget)
                val (width, height) = sizeOf(context, appWidgetManager.getAppWidgetOptions(id))
                views.setImageViewBitmap(
                    R.id.calendar_image,
                    draw(context, width, height, due, LocalDate.now()),
                )
                if (background != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    views.setColorStateList(
                        R.id.widget_root,
                        "setBackgroundTintList",
                        android.content.res.ColorStateList.valueOf(background),
                    )
                }
                // Opens the app (behind the calculator when disguised).
                val open = Intent(context, MainActivity::class.java)
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        context,
                        id,
                        open,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
                appWidgetManager.updateAppWidget(id, views)
            } catch (e: Exception) {
                android.util.Log.e(AuppWidgetProvider.TAG, "Failed to update calendar $id", e)
            }
        }
        scheduleMidnight(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        context.getSystemService(AlarmManager::class.java).cancel(midnightIntent(context))
    }

    /** Redraws right after midnight: today moves and the colors change. */
    private fun scheduleMidnight(context: Context) {
        val zone = java.time.ZoneId.systemDefault()
        val at = LocalDate.now().plusDays(1).atStartOfDay(zone)
            .plusMinutes(1).toInstant().toEpochMilli()
        context.getSystemService(AlarmManager::class.java)
            .set(AlarmManager.RTC, at, midnightIntent(context))
    }

    private fun midnightIntent(context: Context): PendingIntent {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, AuppCalendarWidgetProvider::class.java),
        )
        val intent = Intent(context, AuppCalendarWidgetProvider::class.java)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun backgroundColor(widgetData: SharedPreferences): Int? {
        val key = "aupp_background_color"
        if (!widgetData.contains(key)) return null
        return try {
            widgetData.getInt(key, 0)
        } catch (e: ClassCastException) {
            runCatching { widgetData.getLong(key, 0L).toInt() }.getOrNull()
        }
    }

    /** The widget's size in pixels (portrait: min width, max height). */
    private fun sizeOf(context: Context, options: Bundle): Pair<Int, Int> {
        val density = context.resources.displayMetrics.density
        val w = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).takeIf { it > 0 } ?: 250
        val h = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 } ?: 200
        return Pair((w * density).toInt(), (h * density).toInt())
    }

    private fun draw(
        context: Context,
        width: Int,
        height: Int,
        due: Set<LocalDate>,
        today: LocalDate,
    ): Bitmap {
        val dp = context.resources.displayMetrics.density
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val pad = 12 * dp
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
        }

        // Month name, as any calendar.
        val locale = Locale.forLanguageTag("pt-BR")
        val month = today.month.getDisplayName(TextStyle.FULL_STANDALONE, locale)
            .replaceFirstChar { it.titlecase(locale) }
        val header = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ON_SURFACE
            textSize = 15 * dp
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        }
        var y = pad - header.ascent()
        canvas.drawText(month, pad, y, header)
        header.apply {
            color = DIM
            textSize = 12 * dp
            typeface = Typeface.DEFAULT
            textAlign = Paint.Align.RIGHT
        }
        canvas.drawText(today.year.toString(), width - pad, y, header)
        y += header.descent() + 8 * dp

        // Weekday initials, Sunday first.
        val cellW = (width - 2 * pad) / 7f
        text.textSize = 10 * dp
        text.color = DIM
        y -= text.ascent()
        for ((i, d) in listOf("D", "S", "T", "Q", "Q", "S", "S").withIndex()) {
            canvas.drawText(d, pad + cellW * (i + 0.5f), y, text)
        }
        y += text.descent() + 4 * dp

        // Six weeks from the Sunday on or before the 1st: the days around
        // the month show too (dimmed), the next month's first bills with them.
        val first = today.withDayOfMonth(1)
        val start = first.minusDays((first.dayOfWeek.value % 7).toLong())
        val cellH = (height - pad - y) / 6f
        val radius = minOf(cellW, cellH) / 2f * 0.84f
        text.textSize = minOf(radius * 0.95f, 14 * dp)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.5f * dp
            color = ON_SURFACE
        }
        for (week in 0 until 6) {
            for (col in 0 until 7) {
                val day = start.plusDays((week * 7 + col).toLong())
                val cx = pad + cellW * (col + 0.5f)
                val cy = y + cellH * (week + 0.5f)
                val inMonth = day.month == today.month
                val color = if (day in due) colorFor(day, today) else null
                if (color != null) {
                    fill.color = color
                    fill.alpha = if (inMonth) 255 else 150
                    canvas.drawCircle(cx, cy, radius, fill)
                }
                if (day == today) {
                    canvas.drawCircle(
                        cx, cy,
                        if (color != null) radius + 2.5f * dp else radius,
                        ring,
                    )
                }
                text.color = when {
                    color != null -> 0xFFFFFFFF.toInt()
                    inMonth -> ON_SURFACE
                    else -> FAINT
                }
                text.typeface = if (color != null || day == today) {
                    Typeface.DEFAULT_BOLD
                } else {
                    Typeface.DEFAULT
                }
                val baseline = cy - (text.ascent() + text.descent()) / 2
                canvas.drawText(day.dayOfMonth.toString(), cx, baseline, text)
            }
        }
        return bitmap
    }

    private fun colorFor(day: LocalDate, today: LocalDate): Int = when {
        !day.isAfter(today) -> RED
        day == today.plusDays(1) -> ORANGE
        else -> GREEN
    }

    companion object {
        private const val KEY_DUE = "aupp_calendar_due"
        private const val ON_SURFACE = 0xE6FFFFFF.toInt()
        private const val DIM = 0x99FFFFFF.toInt()
        private const val FAINT = 0x4DFFFFFF
        private const val GREEN = 0xFF43A047.toInt()
        private const val ORANGE = 0xFFFB8C00.toInt()
        private const val RED = 0xFFE53935.toInt()
    }
}
