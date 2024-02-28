package xyz.silberberg.ftagarminconnect
/*
import android.os.ConditionVariable
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice

class GarminSender(service: GarminCommunicationService, private val useAdb: Boolean) : RateLimitedRetryingWatchMessageSender<Message, Map<Int, Any>>(service), ConnectIQ.IQDeviceEventListener {
    @Volatile
    private var connected = false
    private val connectionCondition = ConditionVariable()
    @Volatile
    private var requestOpen = true

    private var connectIQ: ConnectIQ? = null
    private var device: IQDevice? = null
    private var app: IQApp? = null

    private val handler = Handler(Looper.getMainLooper())

    fun startInit() {
        Log.d(TAG, "ConnectIQ Init started")
        val communicationStrategy = if (useAdb) ConnectIQ.IQConnectType.TETHERED else ConnectIQ.IQConnectType.WIRELESS
        connectIQ = ConnectIQ.getInstance(service, communicationStrategy)
        connectIQ!!.initialize(service, false, object : ConnectIQ.ConnectIQListener {
            override fun onSdkReady() {
                onIqInitialize()
            }

            override fun onInitializeError(err: ConnectIQ.IQSdkErrorStatus?) {
                Log.e(TAG, "SDK Error $err")
            }

            override fun onSdkShutDown() {
                Log.e(TAG, "SDK Shutting Down")
            }
        })
    }

    private fun onIqInitialize() {
        Log.d(TAG, "ConnectIQ Initialized")
        val knownDevices = connectIQ!!.knownDevices.filter { d -> SupportedDevices.contains(d.friendlyName) }
        if (knownDevices.isEmpty()) {
            Log.e(TAG, "Could not find a supported device paired to this smart phone!")
            Toast.makeText(service, "No Supported Garmin Device Connected", Toast.LENGTH_LONG).show()
            return
        }

        for (device in knownDevices) {
            connectIQ!!.registerForDeviceEvents(device, this)
        }
    }

    override fun onDeviceStatusChanged(device: IQDevice?, status: IQDevice.IQDeviceStatus?) {
        if (device == null || status == null) {
            Log.e(TAG, "Received null device or status from the SDK")
            shutdown()
            return
        }

        Log.d(TAG, "Device ${device.friendlyName} status changed to $status")
        if (status == IQDevice.IQDeviceStatus.CONNECTED || (useAdb && status == IQDevice.IQDeviceStatus.UNKNOWN)) {
            this.device = device
            getAppInfo()
        } else if (this.device == null) {
            // If another device connected, don't worry about this one
            connected = false
            connectionCondition.close()
        }
    }

    private fun getAppInfo() {
        assert(device != null)
        Log.d(TAG, "Getting application info")
        connectIQ!!.getApplicationInfo(AppId, device, object : ConnectIQ.IQApplicationInfoListener {
            override fun onApplicationInfoReceived(app: IQApp?) {
                if (app == null) {
                    Log.e(TAG, "Received null app from Garmin SDK!")
                    return
                }
                onAppInfoReceived(app)
            }

            override fun onApplicationNotInstalled(appId: String?) {
                Toast.makeText(service, "Monitor Application not installed! Install from settings and restart the app.", Toast.LENGTH_LONG).show()
            }
        })
    }

    private fun onAppInfoReceived(app: IQApp) {
        Log.d(TAG, "Received application info")
        if (app.status != IQApp.IQAppStatus.INSTALLED && app.status != IQApp.IQAppStatus.UNKNOWN) {
            Log.e(TAG, "App is not set up! Status: ${app.status}")
            Toast.makeText(service, "App is not installed!", Toast.LENGTH_LONG).show()
            return
        }

        this.app = app
        connected = true
        connectionCondition.open()
    }

    override fun startApp() {
//        requestOpen = if (!connected) {
//            true
//        } else {
//            Log.d(TAG, "Opening app")
//            handler.post({
//                connectIQ!!.openApplication(device, app, { _, _, status ->
//                    Log.d(TAG, "App status is $status")
//                })
//            })
//            false
//        }
    }

    override fun run() {
        fun checkInterrupted() {
            if (Thread.interrupted()) {
                Thread.currentThread().interrupt()
                running = false
            }
        }
        running = true
        while (running) {
            checkInterrupted()
            if (!running) break

            if (!connected) {
                connectionCondition.block()
                assert(connected || !running)
            }

            checkInterrupted()
            if (!running) break

            if (requestOpen) {
                startApp()
            }

            processMessages()
        }
    }

    override fun Message.convertMessage(): Message {
        return this
    }

    override fun packMessages(messages: Map<Int, Message>): Map<Int, Any> {
        val map = HashMap<Int, Any>()
        var shouldVibrate = false
        for (messagePair in messages) {
            val message = messagePair.value
            when (message) {
                is TeamMessage -> {
                    shouldVibrate = shouldVibrate || message.shouldVibrate
                    map[message.key] = message.teamMessage as Any
                }
                is BatteryMessage -> {
                    shouldVibrate = shouldVibrate || message.shouldVibrate
                    map[message.key] = message.battery as Any
                }
                is MatchMessage -> {
                    map[message.key] = message.matchState
                }
                else -> throw IllegalArgumentException("Unexpected value $message")
            }
        }

        if (shouldVibrate) {
            map[VIBE] = true
        }

        return map
    }

    override fun sendMessages(messages: Map<Int, Any>) {
        assert(connectIQ != null && device != null && app != null)
        connectIQ!!.sendMessage(device, app, messages) { _, _, status ->
            Log.d(TAG, "Sent message with $status")
            when (status) {
                ConnectIQ.IQMessageStatus.SUCCESS -> endSend()
                ConnectIQ.IQMessageStatus.FAILURE_DURING_TRANSFER -> retry()
                else -> {
                    if (status == ConnectIQ.IQMessageStatus.FAILURE_UNKNOWN && useAdb) {
                        // There's some quirk with the simulator returning SUCCESS then unknown failure
                        // https://forums.garmin.com/forum/developers/connect-iq/1265763-questions-regarding-communications-api-and-transmit
                        // Do nothing
                        return@sendMessage
                    }
                    Log.e(TAG, "Received message error $status!")
                    shutdown()
                }
            }
        }
    }

    override fun shutdown() {
        super.shutdown()
        if (connectIQ != null) {
            connectIQ!!.unregisterAllForEvents()
            connectIQ!!.shutdown(service)
            connectIQ = null
        }
        connectionCondition.open()
    }

    companion object {
        private const val AppId = "fc4cdb94-9339-44e4-ad86-2d235312f0e7"
        private val TAG = GarminSender::class.java.name
        private val SupportedDevices = listOf("vivoactive HR", "Simulator", "vívoactive 3")
        private const val VIBE = 7
    }
}*/