@file:OptIn(ExperimentalCoroutinesApi::class)

package xyz.silberberg.ftagarminconnect

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.widget.Toast
import androidx.lifecycle.MutableLiveData
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "GarminConnection"
private val SupportedDevices = listOf("vivoactive HR", "Simulator", "vívoactive 3", "fenix 7")
private const val AppId = "fc4cdb94-9339-44e4-ad86-2d235312f0e7"
private const val VIBE = 7

class GarminService : Service() {
    private val binder = LocalBinder(this)
    private val lock = Any()

    val connectionState = MutableLiveData<Boolean>()
    val messageChannel = Channel<Message>()

    private var connectIQ: ConnectIQ? = null
    private var device: IQDevice? = null
    private var app: IQApp? = null
    private var senderCoroutineScope = CoroutineScope(Dispatchers.IO)
    private val lastUnsentMessages = ConcurrentHashMap<Int, Any>()

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        synchronized(lock) {
            if (connectIQ == null) {
                connectIQ = ConnectIQ.getInstance(this, ConnectIQ.IQConnectType.WIRELESS)
                connectIQ?.initialize(this, true, object : ConnectIQ.ConnectIQListener {
                    override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus?) {
                        Log.e(TAG, "Garmin ConnectIQ initialization error: $status")
                        stopSelf()
                        connectionState.postValue(false)
                    }

                    override fun onSdkReady() {
                        Log.d(TAG, "Garmin ConnectIQ SDK ready")
                        this@GarminService.onSdkReady()
                    }

                    override fun onSdkShutDown() {
                        Log.d(TAG, "Garmin ConnectIQ SDK shut down")
                        stopSelf()
                        connectionState.postValue(false)
                    }
                })
            }
        }

        return START_NOT_STICKY
    }

    private fun onSdkReady() {
        synchronized(lock) {
            val knownDevices =
                connectIQ!!.knownDevices.filter { d ->
                    SupportedDevices.any {
                        d.friendlyName.contains(it)
                    }
                }
            if (knownDevices.isEmpty()) {
                Log.e(TAG, "Could not find a supported device paired to this smart phone!")
                Handler(Looper.getMainLooper()).post {
                    Toast.makeText(
                        this@GarminService,
                        "No Supported Garmin Device Connected",
                        Toast.LENGTH_LONG
                    ).show()
                }

                stopSelf()
                connectionState.postValue(false)
                return
            }

            device = knownDevices.first()
            connectIQ!!.registerForDeviceEvents(device, object : ConnectIQ.IQDeviceEventListener {
                override fun onDeviceStatusChanged(
                    device: IQDevice?,
                    status: IQDevice.IQDeviceStatus?
                ) {
                    if (device == null || status == null) {
                        Log.e(TAG, "Received null device or status from the SDK")
                        return
                    }

                    Log.d(TAG, "Device ${device.friendlyName} status changed to $status")
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                        getAppInfo()
                    } else {
                        connectionState.postValue(false)
                        stopSend()
                    }
                }
            })
        }
    }

    private fun getAppInfo() {
        connectIQ!!.getApplicationInfo(
            AppId,
            device,
            object : ConnectIQ.IQApplicationInfoListener {
                override fun onApplicationInfoReceived(app: IQApp?) {
                    if (app == null) {
                        Log.e(TAG, "Received null app from Garmin SDK!")
                        connectionState.postValue(false)
                        stopSelf()
                        return
                    }

                    Log.d(TAG, "Received app info for ${app.displayName}")

                    synchronized(lock) {
                        this@GarminService.app = app
                    }

                    startSend()
                }

                override fun onApplicationNotInstalled(appId: String?) {
                    Handler(Looper.getMainLooper()).post {
                        Toast.makeText(
                            this@GarminService,
                            "Monitor Application not installed! Install from settings and restart the app.",
                            Toast.LENGTH_LONG
                        ).show()
                    }

                    stopSelf()
                    connectionState.postValue(false)
                }
            })
    }

    private fun startSend() {
        Log.d(TAG, "Starting message sender")
        synchronized(lock) {
            connectionState.postValue(true)
            resetCoroutine()
            Log.d(TAG, "Launching message sender")
            senderCoroutineScope.launch {
                // Send the last messages for each item that were observed while the device was disconnected
                Log.d(TAG, "Sending ${lastUnsentMessages.size} unsent messages")
                sendMessages(connectIQ!!, device!!, app!!, lastUnsentMessages, false)
                Log.d(TAG, "Launching wait and send routine")
                waitAndSendMessages(connectIQ!!, device!!, app!!, messageChannel, false)
            }
        }
    }

    private suspend fun waitAndSendMessages(
        connectIQ: ConnectIQ,
        device: IQDevice,
        app: IQApp,
        messageChannel: Channel<Message>,
        useAdb: Boolean
    ) {
        messageChannel.receiveAsFlow().timedChunk(50.milliseconds).collect { messages ->
            val dedupedMessages = messages.associateBy { it.key }

            val map = HashMap<Int, Any>()
            var shouldVibrate = false
            for (messagePair in dedupedMessages) {
                val message = messagePair.value
                shouldVibrate = shouldVibrate || message.shouldVibrate
                map[message.key] = message.value
            }

            if (shouldVibrate) {
                map[VIBE] = true
            }

            sendMessages(connectIQ, device, app, map, useAdb)
        }
    }

    private suspend fun sendMessages(
        connectIQ: ConnectIQ,
        device: IQDevice,
        app: IQApp,
        messages: Map<Int, Any>,
        useAdb: Boolean
    ) {
        suspend fun trySend() =
            suspendCancellableCoroutine {
                connectIQ.sendMessage(
                    device,
                    app,
                    messages
                ) { _, _, status ->
                    when (status) {
                        ConnectIQ.IQMessageStatus.SUCCESS -> it.resume(true) { _, _, _ -> }
                        ConnectIQ.IQMessageStatus.FAILURE_DURING_TRANSFER -> it.resume(false) { _, _, _ -> }
                        else -> {
                            if (status == ConnectIQ.IQMessageStatus.FAILURE_UNKNOWN && useAdb) {
                                // There's some quirk with the simulator returning SUCCESS then unknown failure
                                // https://forums.garmin.com/forum/developers/connect-iq/1265763-questions-regarding-communications-api-and-transmit
                                // Do nothing
                                return@sendMessage
                            }
                            Log.e(TAG, "Failed to send message with status $status")
                            it.cancel()
                        }
                    }
                }
            }

        for (i in 0 until 3) {
            val sendSucceeded = trySend()

            if (sendSucceeded) {
                return
            }

            val delayAmount = ((i + 1) * 10).milliseconds
            Log.e(TAG, "Failed to send messages, retrying in $delayAmount")
            delay(delayAmount)
        }

        val sendSucceeded = trySend()

        if (!sendSucceeded) {
            Log.e(TAG, "Failed to send messages")
        }
    }

    private fun stopSend() {
        synchronized(lock) {
            resetCoroutine()
            lastUnsentMessages.clear()
            senderCoroutineScope.launch {
                var shouldVibrate = false
                messageChannel.receiveAsFlow().collect {
                    lastUnsentMessages[it.key] = it.value
                    shouldVibrate = shouldVibrate || it.shouldVibrate
                    lastUnsentMessages[VIBE] = shouldVibrate
                }
            }
        }
    }

    private fun resetCoroutine() {
        synchronized(lock) {
            senderCoroutineScope.cancel()
            senderCoroutineScope = CoroutineScope(Dispatchers.IO)
        }
    }

    override fun onDestroy() {
        synchronized(lock) {
            connectIQ?.unregisterAllForEvents()
            connectIQ?.shutdown(this)
            connectIQ = null
            device = null
            app = null
            stopSend()
            connectionState.postValue(false)
        }
        super.onDestroy()
    }
}