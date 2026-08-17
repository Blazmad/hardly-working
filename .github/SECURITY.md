# Security Policy

## Supported version

Only the latest release receives fixes. Download it from
[Releases](https://github.com/Blazmad/hardly-working/releases/latest).

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/Blazmad/hardly-working/security/advisories/new).
Please do not open a public issue for a security problem.

This is a solo, unpaid project: expect a first reply within two weeks. There is
no bug bounty.

## Verifying what you downloaded

The app is signed with an Apple Developer ID certificate and notarized by Apple,
so macOS verifies it before the first launch. To check a downloaded DMG yourself:

```bash
# Apple's verdict — expect "accepted" and "Notarized Developer ID"
spctl -a -t open --context context:primary-signature -v HardlyWorking-1.0.1.dmg

# Who signed it — expect Team ID 272BX4J7SG
codesign -dv --verbose=2 HardlyWorking-1.0.1.dmg 2>&1 | grep -E 'Authority|TeamIdentifier'

# Integrity — compare against the SHA-256 published in the release notes
shasum -a 256 HardlyWorking-1.0.1.dmg
```

## What the app is allowed to do

- It needs the **Accessibility** permission, because macOS requires it to post a
  synthetic mouse event. Nothing else grants that.
- It posts `.mouseMoved` events only, never a click. No keyboard events.
- It makes **no network connection**, has no analytics, and reads no file of
  yours. The only state it stores is two values in its own preferences.
