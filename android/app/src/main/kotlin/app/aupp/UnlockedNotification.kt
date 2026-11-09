package app.aupp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Fork: with the disguise calculator on, says the app is unlocked and until
 * when (Dart: CalculatorGate). It does not name the app's purpose: it shows
 * on the lock screen and the notification shade. "Bloquear agora" sends
 * [ACTION_LOCK] to MainActivity's receiver.
 */
object UnlockedNotification {
    const val ACTION_LOCK = "app.aupp.LOCK"
    private const val CHANNEL_ID = "unlocked"
    private const val NOTIFICATION_ID = 7001

    /** [until] null: unlocked while the app is open (no countdown yet). */
    fun show(context: Context, until: Long?) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL_ID) == null
        ) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Desbloqueado",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Enquanto não precisa digitar o código de novo"
                    setShowBadge(false)
                },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            builder.setContentIntent(PendingIntent.getActivity(context, 0, it, flags))
        }
        val lock = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_LOCK).setPackage(context.packageName),
            flags,
        )
        builder
            .setSmallIcon(R.drawable.ic_stat_unlocked)
            .setContentTitle("Desbloqueado")
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .addAction(
                Notification.Action.Builder(null, "Bloquear agora", lock).build(),
            )
        if (until == null) {
            builder.setContentText(
                "Bloqueia 10 min depois de sair, ou ao bloquear o celular.",
            )
        } else {
            val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(until))
            builder
                .setContentText("Bloqueia às $time, ou ao bloquear o celular.")
                .setWhen(until)
                .setShowWhen(true)
                .setUsesChronometer(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                builder.setChronometerCountDown(true)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setTimeoutAfter(maxOf(0L, until - System.currentTimeMillis()))
            }
        }
        try {
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (e: SecurityException) {
            // Notifications not allowed: the lock works the same.
        }
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }
}
