# FTA Garmin Monitor

FTA Garmin Monitor brings the FIRST Robotics Competition field monitor to a
Garmin watch, helping field technical advisors see robot and match status while
moving around the field.

The Android companion connects to the field monitor over Wi-Fi or Ethernet and
forwards updates to the paired watch. The watch displays match state and, for
both alliances, team numbers, robot status, and battery voltages.

## Getting started

Use a phone running Android 8 or later, paired through Garmin Connect with a
vivoactive HR, vivoactive 3, or fenix 7S.

1. Install the Android companion and the watch app.
2. Connect the phone to the field network, enter the field monitor's SignalR
   address in the companion, and enable the service. Select Ethernet if needed.
3. Open the watch app and check the connection indicators in the companion.

## Building

On Windows, building both apps requires PowerShell 7, JDK 17, Android SDK 36,
the Connect IQ SDK and device definitions, and a Garmin developer key. Select
the SDK in Connect IQ SDK Manager and place the key at the repository root as
`developer_key` or `developer_key.der`:

```powershell
.\build.ps1
```

The Android APK is written to `companion\app\build\outputs\apk\debug\` and
the watch PRGs to `watch\bin\`. Use `.\build.ps1 -Target Android` or
`.\build.ps1 -Target Watch` to build either app separately. The `-GarminSdk` and
`-GarminDeveloperKey` parameters override the selected SDK and local key.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributor guidance.
