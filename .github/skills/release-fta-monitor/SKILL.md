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

Run the helper in preview mode:

```powershell
.\scripts\prepare-release.ps1 -Commit '<full-commit-sha>' -Title '<release-title>' -Preview
```

Add `-PreviousTag '<tag>'` only if the user requested a specific starting tag.
Show the user the exact title and complete generated notes, plus the title and
body of the automatic version-bump PR from `scripts\create-version-pr.ps1` on
`origin/main`. Ask for explicit approval to publish the release and create
that PR. If they decline or want edits, stop rather than dispatching unapproved
text.

After approval, fetch `origin/main` again and check that the version-bump PR
wording still matches what the user approved. Then run the helper with the same
arguments, replacing `-Preview` with `-ApprovedPreviewHash '<preview-sha256>'`
using the hash from the preview. The helper dispatches only if the repository,
commit, tag, title, and notes still match the approved preview. If the PR
wording or preview details changed, show the revised text and obtain approval
again. Never run the approved mode without the user's explicit approval of the
exact text.

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
