package xyz.silberberg.ftagarminconnect

import android.app.Notification
import android.app.PendingIntent
import android.app.PendingIntent.FLAG_IMMUTABLE
import android.app.PendingIntent.FLAG_UPDATE_CURRENT
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.Observer
import com.microsoft.signalr.HubConnection
import com.microsoft.signalr.HubConnectionBuilder
import com.microsoft.signalr.HubConnectionState
import com.microsoft.signalr.messagepack.MessagePackHubProtocol
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.launch

const val FIELD_MONITOR_URI_EXTRA = "field_monitor_uri_extra"

const val LIFECYCLE_INTENT_EXTRA = "lifecycle_intent_extra"
const val START = 0

const val RECONNECT = 1

// Used when we're not on WiFi, but the service has been started and we want to wait until we see
// wifi again
const val DISCONNECT_BUT_KEEP_FOREGROUND = 2
const val STOP = 3

private const val NOTIFICATION_ID = 3

const val NOTIFICATION_CHANNEL = "signalr_connection"

class FieldMonitorConnectionService : Service() {

    private val binder = LocalBinder(this)
    private var hubConnection: HubConnection? = null
    private var lastUrl: String? = null
    private val lock: Any = Any()

    private var networkChangeReceiver: NetworkChangeReceiver? = null
    private var garminServiceConnection: ServiceConnection? = null
    private var garminService: GarminService? = null
    private var sendCoroutineScope: CoroutineScope? = null
    private var observerScope: CoroutineScope? = null

    val connectionState = MutableLiveData(FieldConnectionState.Disconnected)
    val serviceEnabled = MutableLiveData(false)

    private val connectionStateObserver = Observer<FieldConnectionState> { state ->
        val notification = createNotification(state)
        startForeground(NOTIFICATION_ID, notification)

        garminServiceConnection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                val binder = service as LocalBinder
                garminService = binder.service as GarminService
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                garminService = null
            }
        }

        Intent(this, GarminService::class.java).also { intent ->
            bindService(intent, garminServiceConnection!!, Context.BIND_AUTO_CREATE)
        }
    }

    override fun onCreate() {
        super.onCreate()

        connectionState.observeForever(connectionStateObserver)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        synchronized(lock) {
            when (intent?.getIntExtra(LIFECYCLE_INTENT_EXTRA, -1)) {
                START -> {
                    val requestedUrl = intent.getStringExtra(FIELD_MONITOR_URI_EXTRA)
                    if (requestedUrl == lastUrl && connectionState.value != FieldConnectionState.Disconnected) {
                        // Someone else already started a connection to the same URL, nothing to do.
                        return START_NOT_STICKY
                    }

                    lastUrl = if (requestedUrl == null) {
                        Log.e("FieldMonitorConnectionService", "No URL provided to connect to")
                        return START_NOT_STICKY
                    } else {
                        requestedUrl
                    }

                    if (networkChangeReceiver == null) {
                        networkChangeReceiver = NetworkChangeReceiver()
                    }

                    // This will immediately cause a callback with the current network settings. That will then
                    // tell us to connect or not, depending on whether we're on WiFi or not, sending either
                    // RECONNECT or DISCONNECT_BUT_KEEP_FOREGROUND.
                    networkChangeReceiver!!.register()

                    serviceEnabled.postValue(true)

                    return START_NOT_STICKY
                }

                RECONNECT -> {
                    val hubUrl = when (connectionState.value) {
                        FieldConnectionState.Connecting, FieldConnectionState.Connected -> return START_NOT_STICKY
                        else -> {
                            Log.d("FieldMonitorConnectionService", "Reconnecting to $lastUrl")
                            lastUrl!!
                        }
                    }

                    hubConnection?.stop()

                    hubConnection = HubConnectionBuilder
                        .create(hubUrl)
                        .withHubProtocol(MessagePackHubProtocol())
                        .build()

                    hubConnection!!.onClosed {
                        connectionState.postValue(FieldConnectionState.Disconnected)
                    }

                    val observerScope = CoroutineScope(Dispatchers.IO)
                    this.observerScope = observerScope
                    val matchFlow = registerMatchStatusInfoChanged(hubConnection!!, observerScope)
                    val teamChannel = registerFieldMonitorDataReceived(hubConnection!!, matchFlow, observerScope)
                    hubConnection!!.on("robotVersionDataChanged", { }, Any::class.java)
                    observerScope.launch {
                        matchFlow.collect {
                            teamChannel.send(MatchMessage(MATCH_STATE, it.ordinal))
                        }
                    }

                    connectionState.postValue(FieldConnectionState.Connecting)

                    for (i in 0..5) {
                        try {
                            hubConnection!!.start()
                                .doOnComplete { connectionState.postValue(FieldConnectionState.Connected) }
                                .doOnError { connectionState.postValue(FieldConnectionState.Disconnected) }
                                .blockingAwait()
                            break
                        } catch (e: Exception) {
                            Log.w(
                                "FieldMonitorConnectionService",
                                "Received exception from signalr, retrying in 1 second"
                            )
                            Thread.sleep(1000)
                        }
                    }

                    if (hubConnection!!.connectionState != HubConnectionState.CONNECTED) {
                        Log.e("FieldMonitorConnectionService", "Failed to connect to signalr")
                        stopSelf()
                        return START_NOT_STICKY
                    }

                    sendCoroutineScope = CoroutineScope(Dispatchers.Default)
                    sendCoroutineScope!!.launch {
                        teamChannel.consumeAsFlow().collect {
                            garminService?.messageChannel?.send(it)
                        }
                    }

                    return START_NOT_STICKY
                }

                DISCONNECT_BUT_KEEP_FOREGROUND -> {
                    stopConnection(unregisterForNetworkEvents = false)
                    return START_NOT_STICKY
                }

                STOP -> {
                    stopSelf()
                    stopConnection(unregisterForNetworkEvents = true)
                    stopForeground(STOP_FOREGROUND_DETACH)
                    serviceEnabled.postValue(false)
                    return START_NOT_STICKY
                }

                else -> {
                    Log.e("FieldMonitorConnectionService", "Invalid lifecycle intent extra")
                    return START_NOT_STICKY
                }
            }
        }
    }

    override fun onBind(intent: Intent): IBinder = binder

    private fun stopConnection(unregisterForNetworkEvents: Boolean) {
        synchronized(lock) {
            hubConnection?.stop()
            sendCoroutineScope?.cancel()
            sendCoroutineScope = null
            observerScope?.cancel()
            observerScope = null
            if (unregisterForNetworkEvents) {
                networkChangeReceiver?.unregister()
                networkChangeReceiver = null
            }
        }
    }

    override fun onDestroy() {
        stopConnection(unregisterForNetworkEvents = true)
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

    inner class NetworkChangeReceiver {
        private val connectivityManager =
            this@FieldMonitorConnectionService.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        private val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                sendIntent(RECONNECT)
            }

            override fun onLost(network: Network) {
                sendIntent(DISCONNECT_BUT_KEEP_FOREGROUND)
            }

            private fun sendIntent(lifeCycle: Int) {
                val serviceIntent = Intent(
                    this@FieldMonitorConnectionService,
                    FieldMonitorConnectionService::class.java
                )
                serviceIntent.putExtra(LIFECYCLE_INTENT_EXTRA, lifeCycle)
                this@FieldMonitorConnectionService.startService(serviceIntent)
            }
        }

        fun register() {
            val networkRequest = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()

            connectivityManager.registerNetworkCallback(networkRequest, networkCallback)
        }

        fun unregister() {
            connectivityManager.unregisterNetworkCallback(networkCallback)
        }
    }
}