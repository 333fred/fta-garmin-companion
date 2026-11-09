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

## Official builds

Successful `main` pushes produce a signed release candidate after the existing
Android and watch checks pass. Other branches and pull requests do not receive
production signing keys. Each candidate is identified by its build run ID,
attempt, and commit SHA.

The candidate contains the Android APK and AAB, device-specific Garmin PRGs, a
Connect IQ Store IQ package, `build-info.json`, and `SHA256SUMS`. Store uploads
and store listing/review steps remain manual.

### Signing setup

Create the GitHub environment `Official Build` and restrict its deployment
branch policy to the **branch** `main`, not matching tags. Leave required
reviewers disabled for automatic candidate builds. Provision these environment
secrets directly in GitHub:

| Secret | Value |
| --- | --- |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | Existing Android release keystore, base64 encoded |
| `ANDROID_RELEASE_KEY_ALIAS` | Release key alias |
| `ANDROID_RELEASE_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_RELEASE_KEY_PASSWORD` | Key password |
| `CIQ_RELEASE_DEVELOPER_KEY_BASE64` | Existing Garmin production PKCS8 DER developer key, base64 encoded |

Add environment variables `ANDROID_RELEASE_CERT_SHA256` (certificate SHA-256)
and `CIQ_RELEASE_PUBLIC_KEY_SHA256` (SHA-256 of the DER SubjectPublicKeyInfo).
Verify that the Android certificate matches installed APKs and the signing
identity accepted for Play uploads, and that the Garmin key matches the store
app's existing key. Do not rotate keys as part of setting up CI.

The existing repository secrets `CIQ_GARMIN_USERNAME`, `CIQ_GARMIN_PASSWORD`,
and variable `CIQ_GARMIN_AGREEMENT_HASH` still provide SDK access. Keep the
separate `CIQ_DEVELOPER_KEY_BASE64` for ordinary watch validation.

For a local signed build, set `ANDROID_HOME` or `ANDROID_SDK_ROOT` and the
environment variables `ANDROID_RELEASE_KEYSTORE_PATH`,
`ANDROID_RELEASE_KEY_ALIAS`, `ANDROID_RELEASE_KEYSTORE_PASSWORD`, and
`ANDROID_RELEASE_KEY_PASSWORD`, then run:

```powershell
.\build.ps1 -Configuration Release
```

Verified release files are staged in `build\official\`; compiler intermediates
are kept outside that directory. `-Target Android` or `-Target Watch` also works
in release mode. Local builds are marked nonofficial and cannot be promoted.
The public Garmin key fingerprint is recorded in `build-info.json`; Android's
certificate fingerprint can also be obtained with `keytool -list -v`.

### Promoting a release

Before a release, update Android `versionName` and the watch manifest version
together, and increase Android `versionCode` beyond previously distributed or
uploaded values. Versions are not assigned automatically by CI.

Run **Promote release** from `main` in GitHub Actions, providing the full commit
SHA and the exact title and notes you have reviewed. The workflow finds the
newest successful main build of that commit with an available official
candidate, verifies it, and creates `v<app-version>` at the commit. It never
moves an existing tag. Historical `v0.x` tags are unchanged.

Promotion uploads the original signed files to a temporary draft, then publishes
a full release with the reviewed text unchanged. It neither rebuilds nor
re-signs. Matching empty drafts, drafts with the matching `build-info.json`, and
published releases can be resumed; conflicting tags, release text, or assets
require manual resolution. Empty starter assets from failed uploads are removed
from matching drafts before retrying. Assets are verified again after
publication; they remain mutable unless release immutability is enabled.

After publication, the workflow opens a PR against `main` to increment the
patch version in both apps and Android `versionCode` by one. If `main` already
has a different version or version code, the release remains published but the
PR step fails rather than overwriting it. After fixing a PR-step failure, use
**Re-run failed jobs** on the same workflow run to retry without selecting
another candidate.

Enable **Allow GitHub Actions to create and approve pull requests** in the
repository's Actions settings for the PR job. Checks on PRs created with
`GITHUB_TOKEN` require approval before they run.
