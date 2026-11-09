# Contributing

## Repository layout

- `companion\` contains the Android app and its Gradle wrapper.
- `watch\` contains the Connect IQ app, resources, and device manifest.
- `build.ps1` builds either or both apps; `scripts\` supports CI and releases.
- `.github\workflows\` contains the build and release workflows.

## Development setup

The shared build script runs on Windows with PowerShell 7. Install JDK 17 and
Android SDK 36. Android Studio can open `companion\`; the project includes its
own Gradle wrapper.

For watch development, install the Connect IQ SDK Manager, select an SDK, and
download the device definitions listed in `watch\manifest.xml`. Create your own
Garmin developer key; the Monkey C extension for VS Code can generate one.
Place it at the repository root as `developer_key` or `developer_key.der`, or
set `GARMIN_DEVELOPER_KEY`. Production signing keys are not needed for local
development.

The script uses the SDK selected in SDK Manager. Set `GARMIN_SDK` or pass
`-GarminSdk` to use another installation.

## Build and validate

From the repository root, build both apps or select one target:

```powershell
.\build.ps1
.\build.ps1 -Target Android
.\build.ps1 -Target Watch
```

The Android build produces a debug APK and runs Android lint. The watch build
produces a PRG for each device in the manifest. Android `versionName` and the
watch manifest version must match, even when building one target.

Run the existing Android unit tests with:

```powershell
.\companion\gradlew.bat -p .\companion ':app:testDebugUnitTest'
```

For watch UI development, start the Connect IQ simulator using `connectiq.bat`
from the SDK's `bin` directory. Once it is running, use `monkeydo.bat` to run a
generated PRG. For example:

```powershell
$sdk = (Get-Content -Raw (Join-Path $env:APPDATA 'Garmin\ConnectIQ\current-sdk.cfg')).Trim()
& (Join-Path $sdk 'bin\monkeydo.bat') '.\watch\bin\fta-monitor-garmin-watchapp-vivoactive3.prg' 'vivoactive3'
```

Use a paired Android phone and compatible watch to verify communication between
the apps.

## Pull requests

Open pull requests against `main` and describe the change and the checks you
ran. CI builds and lints Android and runs its unit tests on pull requests. The
watch build runs on branch pushes or manual dispatches, not on pull requests.

## Releases

For release assistance, use the [release skill](.github/skills/release-fta-monitor/SKILL.md).
