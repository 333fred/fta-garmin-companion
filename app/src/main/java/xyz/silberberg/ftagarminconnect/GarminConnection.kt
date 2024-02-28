@file:OptIn(ExperimentalCoroutinesApi::class, ExperimentalCoroutinesApi::class)

package xyz.silberberg.ftagarminconnect

import android.content.Context
import android.util.Log
import android.widget.Toast
import androidx.lifecycle.MutableLiveData
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.ConnectIQ.IQDeviceEventListener
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

private const val TAG = "GarminConnection"
private val SupportedDevices = listOf("vivoactive HR", "Simulator", "vívoactive 3", "fenix 7")
private const val AppId = "fc4cdb94-9339-44e4-ad86-2d235312f0e7"

fun startGarminConnection(
    messageChannel: Channel<Message>?,
    connectionState: MutableLiveData<Boolean>,
    context: Context
): CoroutineScope {
    val scope = CoroutineScope(Dispatchers.IO)
    scope.launch {
        try {
            connectAndStartGarmin(connectionState, context)
        } finally {
//            connectionState.postValue(false)
        }
    }

    return scope
}

private suspend fun connectAndStartGarmin(
    connectionState: MutableLiveData<Boolean>,
    context: Context
) {
    Log.d(TAG, "ConnectIQ Init started")
    val communicationStrategy = ConnectIQ.IQConnectType.WIRELESS
    val connectIQ = ConnectIQ.getInstance(context, communicationStrategy)

    withContext(Dispatchers.Main) {
        suspendCancellableCoroutine {
            connectIQ.initialize(context, false, object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() {
                    it.resume(Unit, null)
                }

                override fun onInitializeError(err: ConnectIQ.IQSdkErrorStatus?) {
                    Log.e(TAG, "SDK Error $err")
                    connectionState.postValue(false)
                    it.cancel()
                }

                override fun onSdkShutDown() {
                    Log.e(TAG, "SDK Shutting Down")
                    connectionState.postValue(false)
                    it.cancel()
                }
            })
        }
    }

    Log.d(TAG, "ConnectIQ Initialized")

    val knownDevices =
        connectIQ!!.knownDevices.filter { d ->
            SupportedDevices.any {
                d.friendlyName.contains(it)
            }
        }
    if (knownDevices.isEmpty()) {
        Log.e(TAG, "Could not find a supported device paired to this smart phone!")
        withContext(Dispatchers.Main) {
            Toast.makeText(context, "No Supported Garmin Device Connected", Toast.LENGTH_LONG)
                .show()
        }
        return
    }

    var device: IQDevice? = null

    for (knownDevice in knownDevices) {
        device = withContext(Dispatchers.Main) {
            suspendCancellableCoroutine {
                connectIQ.registerForDeviceEvents(knownDevice, object : IQDeviceEventListener {
                    override fun onDeviceStatusChanged(
                        device: IQDevice?,
                        status: IQDevice.IQDeviceStatus?
                    ) {
                        if (device == null || status == null) {
                            Log.e(TAG, "Received null device or status from the SDK")
                            it.cancel()
                            return
                        }

                        Log.d(TAG, "Device ${device.friendlyName} status changed to $status")
                        if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                            it.resume(device, null)
                        } else {
                            it.resume(null, null)
                        }
                    }
                })
            }
        }

        if (device != null) {
            break
        }
    }

    if (device == null) {
        Log.e(TAG, "Could not register for any device events")
        connectionState.postValue(false)
        return
    }

    Log.d(TAG, "Getting application info")

    val app = withContext(Dispatchers.Main) {
        suspendCancellableCoroutine {
            connectIQ.getApplicationInfo(
                AppId,
                device,
                object : ConnectIQ.IQApplicationInfoListener {
                    override fun onApplicationInfoReceived(app: IQApp?) {
                        if (app == null) {
                            Log.e(TAG, "Received null app from Garmin SDK!")
                            connectionState.postValue(false)
                            it.cancel()
                            return
                        }

                        it.resume(app, null)
                    }

                    override fun onApplicationNotInstalled(appId: String?) {
                        Toast.makeText(
                            context,
                            "Monitor Application not installed! Install from settings and restart the app.",
                            Toast.LENGTH_LONG
                        ).show()
                        it.cancel()
                    }
                })
        }
    }


    Log.d(TAG, "Received application info")
    if (app.status != IQApp.IQAppStatus.INSTALLED && app.status != IQApp.IQAppStatus.UNKNOWN) {
        Log.e(TAG, "App is not set up! Status: ${app.status}")
        withContext(Dispatchers.Main) {
            Toast.makeText(context, "App is not installed!", Toast.LENGTH_LONG).show()
        }
        return
    }

    Log.d(TAG, "App is installed!")
    withContext(Dispatchers.Main) {
        connectionState.postValue(true)
    }
}