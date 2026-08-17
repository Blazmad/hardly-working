<p align="center">
  <img src="assets/icon-256.png" alt="Hardly Working" width="128" height="128">
</p>

<h1 align="center">Hardly Working</h1>

<p align="center">
  <em>Working hard, or hardly working?</em>
</p>

A small macOS menu bar app that stops Teams (or Slack, Discord…) from marking you "away" when you step away from your Mac.

**[Download for macOS →](https://blazmad.github.io/hardly-working/)**

## How it works

Teams reads the macOS idle timer: the time since your last keyboard or mouse input. Hardly Working checks that same timer every 20 seconds and, as soon as it passes your chosen threshold, moves the cursor by one pixel and puts it straight back — imperceptible, never a click, and no interference at all if you happen to be using the mouse.

After each nudge the app waits a fraction of a second, long enough for macOS to register the event, then **checks that the timer actually dropped**. A single miss triggers nothing: it takes **two consecutive failures** before the icon switches to its alert state, because an isolated hiccup shouldn't cry wolf. Once the alert is up, only a nudge that succeeds in resetting the timer clears it — or losing and regaining the Accessibility permission, which resets the detection because the cause of the failure is then known. Unchecking and re-checking "Active" on its own will not clear it. The app never claims to be working when it isn't.

## Installation

1. Open the downloaded `HardlyWorking-*.dmg` and drag the app into Applications.
2. Launch the app — a cup icon appears in your menu bar.
3. **Grant the Accessibility permission** (required). On first launch the app doesn't have it yet, so the icon goes straight to the alert triangle — it won't open anything on its own. Click the icon, then "Open Accessibility Settings…" in the menu: that triggers the system prompt and opens System Settings → Privacy & Security. Landing exactly on the "Accessibility" row isn't guaranteed across macOS versions, so you may need to scroll. Tick "Hardly Working". Without this permission, macOS blocks all synthetic mouse movement.

## The menu

| Item | What it does |
|---|---|
| **Active** | The main switch. Unchecked, the app monitors nothing at all. |
| **Idle threshold** | How long to wait before acting: 2, 3, 4, 5 or 10 min. Default: 4 min. |
| **Launch at login** | Start automatically when you log in. Off by default. |

The icon reflects the state: full cup (active), empty cup (paused), triangle (something needs fixing).

### Choosing a threshold

Microsoft doesn't publish the exact delay after which Teams switches you to "away" (estimated at ~5 min, never measured). The 4 min default sits just under it. If your status flips anyway, drop to 3 or 2 min.

## Worth knowing

**Your Mac will no longer sleep on its own** while the app is active: sleep is triggered by the same idle timer. Uncheck "Active" when you leave for the day, or just close the lid.

**More importantly, your screen will no longer lock itself either.** Automatic screen locking relies on that same idle timer — so on a work machine, the exact situation this app is built for (being away for a while) is the one that leaves your session unlocked longer than you'd expect. Lock it yourself on the way out: `Ctrl-Cmd-Q`, or set a hot corner to "Lock Screen" (System Settings → Desktop & Dock → Hot Corners).

## If the icon turns into a triangle

The triangle is the product's only safety mechanism. It covers two distinct causes, told apart by **the banner at the top of the menu**:

- **"Accessibility permission required"** → the permission was never granted, or was revoked. Click "Open Accessibility Settings…" and tick "Hardly Working" under System Settings → Privacy & Security → Accessibility.
- **"Mouse nudge had no effect…"** → the permission is ticked, but mouse movements had no effect on two consecutive cycles. Typically a permission silently revoked by a macOS update (removing and re-adding the tick in Settings often fixes this), or a system restriction (MDM, configuration profile) blocking synthetic mouse events.

Unchecking and re-checking "Active" never clears the alert on its own: only a nudge that succeeds in dropping the idle timer clears it — or losing and regaining the Accessibility permission, which is precisely the remedy for the second case above, since it resets the detection.

### Special case: the app is ticked in Settings, but the triangle persists

A confusing symptom: "Hardly Working" is listed under System Settings → Privacy & Security → Accessibility, the box is ticked, and yet the app still shows the alert. Unticking and re-ticking changes nothing.

The cause: macOS doesn't just record "this app is allowed", it records the app's **designated requirement** — an expression pinning the bundle id, the Apple anchor, the certificate-type marker OIDs and the Team ID:

```
identifier "com.madzar.hardlyworking" and anchor apple generic
and certificate 1[field.1.2.840.113635.100.6.2.6]
and certificate leaf[field.1.2.840.113635.100.6.1.13]
and certificate leaf[subject.OU] = "272BX4J7SG"
```

When a new build no longer satisfies that expression, the entry keeps the same name and the same ticked box but **no longer matches the installed binary**. The tick is just flipping a switch on a stale record.

Renewing the signing certificate does *not* cause this. Measured on 2026-08-17: replacing the Developer ID certificate (old intermediate → G2, new private key) left the requirement byte-identical and the grant intact across the upgrade. What breaks it is a change of Team ID, or moving between certificate classes — an *Apple Development* build and a *Developer ID* build pin different marker OIDs.

The fix is to delete the entry so a fresh one gets created:

```bash
tccutil reset Accessibility com.madzar.hardlyworking
```

Then relaunch the app and grant the permission again. (Manual equivalent: select the entry in the list and click the `−` button, rather than unticking the box.)

This only happens when the designated requirement changes. In normal use the permission never has to be granted again, including across updates.

## Building from source

Requires Xcode and XcodeGen (`brew install xcodegen`).

```bash
xcodegen generate                         # generate the Xcode project from project.yml
open HardlyWorking.xcodeproj              # to develop and debug
bash scripts/build-dmg.sh                 # build the app and produce dist/Hardly Working.dmg
```

`project.yml` is the source of truth — the `.xcodeproj` is generated and not versioned.

Other scripts, none of them needed for a plain build:

| Script | What it does |
|---|---|
| `scripts/make-icon.sh` | regenerates the app icon set from `assets/icon.svg` |
| `scripts/make-favicon.sh` | regenerates the site favicon from `assets/favicon.svg` |
| `scripts/deploy-site.sh` | publishes `site/` to the `gh-pages` branch |
| `scripts/stats.sh` | prints download counts and repository traffic |

### Tests

```bash
xcodegen generate && xcodebuild -project HardlyWorking.xcodeproj \
  -scheme HardlyWorking -destination 'platform=macOS' test
```

The tests cover the pure logic (threshold, settings, state machine, self-verification) without touching the system or moving the real cursor. Verifying that the product does its actual job stays manual: leave the Mac idle and watch the status stay green.

## Distribution

The DMG is signed with a *Developer ID* certificate and **notarized by Apple**, so it installs without any security warning. `scripts/build-dmg.sh` handles this automatically when the certificate and the notarization profile are present on the machine, and skips it otherwise — so the script still works if you clone this repository without an Apple developer account.

## History

Replaces `teams-presence`, an earlier bash-script version. This native v2 removes its three weaknesses: a dependency on Homebrew (`cliclick`), an Accessibility permission that broke on every update, and a workaround for the TCC protection on the `~/Documents` folder.
