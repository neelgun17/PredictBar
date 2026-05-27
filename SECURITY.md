# Security Policy

## Reporting a Vulnerability

This application handles financial API credentials (API keys and RSA private keys). If you discover a security vulnerability, **please do not open a public issue**.

Instead, report it privately via GitHub's [private vulnerability reporting](https://github.com/neelgun17/PredictBar/security/advisories/new). Reports will be acknowledged within 7 days, and the issue will be coordinated and disclosed responsibly once a fix is available.

## Scope

The following are in scope:
- Credential leakage (Keychain bypass, logging secrets, writing keys to disk)
- Code injection or command injection via API responses
- Man-in-the-middle vulnerabilities in API communication
- Signature bypass in the RSA-SHA256 authentication flow

## Design Principles

- Credentials are stored exclusively in the macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecAttrSynchronizable = false`. They never leave the device, are never included in iCloud Keychain sync, and are not included in unencrypted backups.
- The RSA private key is imported into an opaque `SecKey` once per process. The PEM string is dropped immediately after import. The key itself never lives as a Swift `String` in heap memory.
- The API key UUID is read from the Keychain on demand for each request and not cached.
- No secrets are logged, written to UserDefaults, or stored in plaintext.
- All API communication uses HTTPS (TLS 1.2+).
- API requests are signed with RSA-PSS-SHA256 (the algorithm Kalshi requires).
- TLS connections to `api.elections.kalshi.com` use **certificate pinning** against the Amazon CA SPKI hashes. A user who has installed a malicious root CA (corporate MITM, malware, compromised CA) cannot intercept Kalshi API traffic.
- Release builds are signed with the macOS **Hardened Runtime** (`codesign --options runtime`), which blocks debugger attachment and unsigned dynamic library injection.

## What We Cannot Protect Against

We are honest about the limits of a desktop app's security model. The following threats are outside what PredictBar alone can defend against:

- **Malware running as the same user.** macOS does not isolate Keychain items from other apps running as the same user account for generic-password items like ours. If your Mac is compromised, your Kalshi credentials may be too. Keep your Mac up to date and avoid running untrusted software.
- **Clipboard / pasteboard exposure.** When you copy your API key or private key from Kalshi's website to paste into PredictBar, the system pasteboard briefly holds those values. Other running apps can read the clipboard. Clear your clipboard after pasting.
- **Screen recording / screen capture.** Any process with screen recording permission captures the credentials at the moment they're displayed. `SecureField` masks visual display but does not prevent screen recording.
- **Physical access while unlocked.** Anyone with physical access to your unlocked Mac can open the app and use the Kalshi account, just as they could open Kalshi.com in your logged-in browser.
- **Compromise of Kalshi's own systems or Amazon's intermediate CA.** Pinning protects against forged certificates from other CAs but cannot defend against a compromise of the CA we pin to.

## Sandboxing

PredictBar runs **without** the macOS App Sandbox (`com.apple.security.app-sandbox = false`). This is intentional: the app is distributed outside the Mac App Store and needs unrestricted Keychain access to store API credentials and arbitrary outbound network access to reach the Kalshi API and WebSocket endpoints. Network access is the only entitlement granted.
