package app.aupp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Fork: keeps the app process alive (not frozen, CPU awake) while a sync
 * (Dinzo and others) runs in Dart, so locking the phone or leaving the app does
 * not break it. Its notification is the only sync notification: it shows the
 * progress and disappears when the sync ends (Dart calls stop).
 */
class SyncForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Sincronizando…"
        val done = intent?.getIntExtra(EXTRA_DONE, -1) ?: -1
        val total = intent?.getIntExtra(EXTRA_TOTAL, -1) ?: -1
        val notification = build(text, done, total)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "aupp:sync",
            ).also { it.acquire(MAX_DURATION_MS) }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    private fun build(text: String, done: Int, total: Int): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL_ID) == null
        ) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Sincronizando",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Enquanto a Dinzo ou outro serviço sincronizam"
                    setShowBadge(false)
                },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        if (open != null) {
            val flags = android.app.PendingIntent.FLAG_IMMUTABLE or
                android.app.PendingIntent.FLAG_UPDATE_CURRENT
            builder.setContentIntent(
                android.app.PendingIntent.getActivity(this, 0, open, flags),
            )
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_sync)
            .setContentTitle("Sincronizando")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(if (total > 0) total else 0, if (done >= 0) done else 0, total <= 0)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "sync_running"
        private const val NOTIFICATION_ID = 7000
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_DONE = "done"
        private const val EXTRA_TOTAL = "total"
        private const val MAX_DURATION_MS = 15 * 60 * 1000L

        /** Starts the service, or updates its notification if running. */
        fun update(context: Context, text: String?, done: Int?, total: Int?) {
            val intent = Intent(context, SyncForegroundService::class.java)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_DONE, done ?: -1)
                .putExtra(EXTRA_TOTAL, total ?: -1)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SyncForegroundService::class.java))
        }
    }
}
