---
name: release-fta-monitor
description: Prepare, publish, and verify FTA Garmin Monitor releases from signed CI artifacts. Use when asked to release the apps, review release notes, or follow up on a release or its version-bump PR.
---

# Release FTA Garmin Monitor

Use the repository's authenticated GitHub CLI and PowerShell from the repository
root. Never request private keys or passwords in chat. Do not commit, push,
publish, merge, or post written content without the user's explicit approval.

## Prepare

1. Fetch `main` from `origin` and resolve the full SHA of `origin/main`:

   ```powershell
   git fetch origin main
   if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch origin/main.' }
   git rev-parse --verify 'refs/remotes/origin/main^{commit}'
   if ($LASTEXITCODE -ne 0) { throw 'Failed to resolve origin/main.' }
   ```

   If either command fails, stop and report the failure. Show the SHA to the
   user and ask them to confirm whether to release it; do not ask them for a
   SHA. If they decline, stop and wait for their instructions. Also ask whether
   to override GitHub's automatic previous-release selection. Do not assume the
   current branch or latest run is the requested release.
2. Verify that the selected commit has a successful official `main` candidate:

   ```powershell
   .\scripts\select-release-candidate.ps1 -Commit '<full-commit-sha>' -Repository '<owner/repository>'
   ```

   If no candidate is available, stop and report it. Do not substitute a smoke
   artifact, rebuild, or re-sign the release.
3. Read `companion\app\build.gradle.kts` and `watch\manifest.xml` at the
   selected commit, not the current worktree. Check that their versions match
   and confirm Android `versionCode` exceeds the previously distributed code.
   If the previous code is unknown, ask the user. If a version change is
   needed, obtain approval before making or publishing it.
4. Review the release changes and suggest a title using them and the verified
   version. Ask the user to confirm it or provide a different title, and use
   their confirmed title when running the helper.

## Review and publish

Have the user run the helper in their own PowerShell terminal:

```powershell
.\scripts\prepare-release.ps1 -Commit '<full-commit-sha>' -Title '<release-title>'
```

Add `-PreviousTag '<tag>'` only if the user requested a specific starting tag.
The helper generates GitHub release notes, displays the exact title and body,
and asks the user to type `PUBLISH` before dispatch. The user must review and
confirm that text themselves; never supply the confirmation automatically.
If the user declines or wants edits, stop rather than dispatching unapproved text.

The workflow creates the matching `v<version>` tag and publishes the selected
signed artifacts without rebuilding. Do not create or move the tag yourself.

## Follow up

Monitor the dispatched **Promote release** run and report its result. Use the
run URL or ID returned by the helper; if it is unavailable, identify the
matching run and commit before watching it rather than assuming the latest.

After publication, check the GitHub Release and the automatically created
`automation/version-after-v<version>` PR. Do not merge the PR or post replies
without explicit approval. If that PR's CI requires approval, tell the user.
If promotion or the version-PR job fails, report what succeeded and ask before
rerunning or modifying anything; when only the PR job failed, rerun failed
jobs rather than rebuilding or republishing.

```powershell
gh run watch '<run-id>' --repo '<owner/repository>' --exit-status
gh release view 'v<version>' --repo '<owner/repository>' --json tagName,isDraft,isPrerelease,assets,url
gh pr list --repo '<owner/repository>' --base main --head 'automation/version-after-v<version>'
```

Google Play and Connect IQ Store submissions remain manual. Only help submit
the AAB or IQ package when explicitly requested, and obtain approval for any
external content or publication.
