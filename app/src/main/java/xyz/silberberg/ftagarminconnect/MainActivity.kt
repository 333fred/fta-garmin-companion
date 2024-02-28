package xyz.silberberg.ftagarminconnect

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.Bundle
import android.os.IBinder
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.livedata.observeAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.core.app.NotificationManagerCompat
import xyz.silberberg.ftagarminconnect.ui.theme.FTAGarminConnectTheme

class MainActivity : ComponentActivity() {
    private var service by mutableStateOf<FieldMonitorConnectionService?>(null)
    private var serviceConnection: ServiceConnection? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val importance = NotificationManager.IMPORTANCE_LOW
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

        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            val intent =
                Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                }
            startActivity(intent)
        }

        setContent {
            FTAGarminConnectTheme {
                // A surface container using the 'background' color from the theme
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    ConnectionUI(service)
                }
            }
        }

        serviceConnection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                val localBinder = binder as FieldMonitorConnectionService.LocalBinder
                service = localBinder.getService()
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                service = null
            }
        }

        Intent(this, FieldMonitorConnectionService::class.java).also { intent ->
            bindService(intent, serviceConnection!!, Context.BIND_AUTO_CREATE)
        }
    }
}

@Composable
fun ConnectionUI(service: FieldMonitorConnectionService?) {
    var url by remember { mutableStateOf("http://10.0.0.33/fieldMonitorHub") }
    var isValidUrl by remember { mutableStateOf(true) }
    val context = LocalContext.current

    val connectionState by service?.connectionState?.observeAsState(FieldConnectionState.Disconnected)
        ?: remember { mutableStateOf(FieldConnectionState.Disconnected) }

    val serviceEnabled by service?.serviceEnabled?.observeAsState(false)
        ?: remember { mutableStateOf(false) }

    val garminConnected by service?.garminConnected?.observeAsState(false)
        ?: remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "Field Monitor Connection Status",
                style = MaterialTheme.typography.headlineSmall
            )
            Text(text = "Service Enabled: $serviceEnabled")
            Text(
                text = "SignalR Status: $connectionState", color = when (connectionState) {
                    FieldConnectionState.Disconnected, null -> Color.Red
                    FieldConnectionState.Connecting -> Color.Yellow
                    FieldConnectionState.Connected -> Color.Green
                }
            )
            Text(
                text = "Garmin Status: $garminConnected", color = when (garminConnected) {
                    false -> Color.Red
                    true -> Color.Green
                }
            )
            TextField(
                value = url,
                onValueChange = {
                    url = it
                    isValidUrl = android.util.Patterns.WEB_URL.matcher(url).matches()
                },
                label = { Text("SignalR Address") }
            )
            Button(onClick = {
                if (!serviceEnabled) {
                    enableFieldMonitorService(url, context)
                } else {
                    disableFieldMonitorService(context)
                }
            }, enabled = isValidUrl) {
                Text(
                    if (!serviceEnabled) {
                        "Enable Service"
                    } else {
                        "Disable Service"
                    }
                )
            }
        }
    }
}

fun enableFieldMonitorService(urlString: String, context: Context) {
    val intent = Intent(context, FieldMonitorConnectionService::class.java)
    intent.putExtra(FIELD_MONITOR_URI_EXTRA, urlString)
    intent.putExtra(LIFECYCLE_INTENT_EXTRA, START)
    context.startService(intent)
}

fun disableFieldMonitorService(context: Context) {
    val intent = Intent(context, FieldMonitorConnectionService::class.java)
    intent.putExtra(LIFECYCLE_INTENT_EXTRA, STOP)
    context.startService(intent)
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(
        text = "Hello $name!",
        modifier = modifier
    )
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
    FTAGarminConnectTheme {
        Greeting("Android")
    }
}