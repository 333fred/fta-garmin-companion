package xyz.silberberg.ftagarminconnect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PendingIntent.FLAG_IMMUTABLE
import android.app.PendingIntent.FLAG_UPDATE_CURRENT
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Binder
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.Observer
import com.microsoft.signalr.HubConnection
import com.microsoft.signalr.HubConnectionBuilder
import com.microsoft.signalr.messagepack.MessagePackHubProtocol
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.rx3.await

const val FIELD_MONITOR_URI_EXTRA = "field_monitor_uri_extra"

const val LIFECYCLE_INTENT_EXTRA = "lifecycle_intent_extra"
const val START = 0
const val STOP = 2

private const val NOTIFICATION_ID = 3

private const val NOTIFICATION_CHANNEL = "signalr_connection"

class FieldMonitorConnectionService : Service() {

    private val binder = LocalBinder()
    private var hubConnection: HubConnection? = null
    private var coroutineScope: CoroutineScope? = null

    val connectionState: MutableLiveData<FieldConnectionState> =
        MutableLiveData(FieldConnectionState.Disconnected)

    private val connectionStateObserver = Observer<FieldConnectionState> { state ->
        val notification = createNotification(state)
        startForeground(NOTIFICATION_ID, notification)
        if (state == FieldConnectionState.Disconnected) {
            stopForeground(STOP_FOREGROUND_DETACH)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val importance = NotificationManager.IMPORTANCE_HIGH
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL,
            "SignalR Notification Channel",
            importance
        ).apply {
            description = "Foreground notification for SignalR connection status"
        }
        val notificationManager: NotificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)

        connectionState.observeForever(connectionStateObserver)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.getIntExtra(LIFECYCLE_INTENT_EXTRA, -1)) {
            START -> {}
            STOP -> {
                stopSelf()
                stopConnection()
                return START_NOT_STICKY
            }

            else -> {
                Log.e("FieldMonitorConnectionService", "Invalid lifecycle intent extra")
                return START_NOT_STICKY
            }
        }

        hubConnection?.stop()
        coroutineScope?.cancel()
        coroutineScope = CoroutineScope(Dispatchers.IO)

        val hubUrl = intent.getStringExtra(FIELD_MONITOR_URI_EXTRA)

        hubConnection = HubConnectionBuilder
            .create(hubUrl)
            .withHubProtocol(MessagePackHubProtocol())
            .build()

        hubConnection!!.onClosed {
            connectionState.postValue(FieldConnectionState.Disconnected)
        }

        coroutineScope?.launch {
            val hubConnection = hubConnection
            if (hubConnection != null) {
                connectionState.postValue(FieldConnectionState.Connecting)
                hubConnection.start()
                    .doOnComplete { connectionState.postValue(FieldConnectionState.Connected) }
                    .doOnError { connectionState.postValue(FieldConnectionState.Disconnected) }
                    .await()
            } else {
                connectionState.postValue(FieldConnectionState.Disconnected)
            }
        }

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    fun stopConnection() {
        coroutineScope?.cancel()
        coroutineScope = null
        hubConnection?.stop()
    }

    override fun onDestroy() {
        stopConnection()
        connectionState.removeObserver(connectionStateObserver)
        super.onDestroy()
    }

    private fun createNotification(state: FieldConnectionState): Notification {
        val text = when (state) {
            FieldConnectionState.Connecting -> "Connecting to Field Monitor"
            FieldConnectionState.Connected -> "Connected to Field Monitor"
            FieldConnectionState.Disconnected -> "Disconnected from Field Monitor"
        }

        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                notificationIntent,
                FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE
            )

        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL)
            .setContentTitle("Field Monitor Connection")
            .setContentText(text)
            .setSmallIcon(R.drawable.big_logo)
            .setContentIntent(pendingIntent)

        if (state == FieldConnectionState.Connected) {
            val closeConnectionIntent = Intent(this, FieldMonitorConnectionService::class.java)
            closeConnectionIntent.putExtra(LIFECYCLE_INTENT_EXTRA, STOP)
            val closeConnectionPendingIntent =
                PendingIntent.getService(
                    this,
                    0,
                    closeConnectionIntent,
                    FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE
                )

            builder.addAction(
                R.drawable.ic_action_remove,
                "Close Connection",
                closeConnectionPendingIntent
            )
        }

        return builder.build()
    }

    inner class LocalBinder : Binder() {
        fun getService(): FieldMonitorConnectionService = this@FieldMonitorConnectionService
    }
}