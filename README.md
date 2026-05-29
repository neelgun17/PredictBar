# PredictBar

A native macOS menu bar application for tracking your prediction market portfolio, positions, and ROI in real-time.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Screenshots

<p align="center">
  <img src="screenshots/dropdown.png" alt="PredictBar dropdown showing positions, P&L, and ROI" width="420">
</p>
<p align="center">
  <img src="screenshots/menubar.png" alt="PredictBar menu bar item" width="160">
</p>

## Features

- **Real-time Portfolio Tracking** - View your total portfolio value, cash balance, and ROI directly in the menu bar
- **Position Management** - See all active positions with current price, average entry, quantity, profit/loss, ROI, and one-click sell/hedge shortcuts
- **Smart Alerts** - Get notified when positions hit customizable ROI thresholds, profit targets, price targets, stop-loss levels, or arbitrage/hedge opportunities
- **Per-Position Alerts** - Configure individual alert settings for each position
- **Multiple Display Modes** - Choose what to show in the menu bar: Cash Out Value, ROI %, P&L, Portfolio Value, or Balance
- **Secure Storage** - API credentials stored in macOS Keychain (never saved to disk)
- **Native Experience** - Built with SwiftUI, designed to feel like a native macOS app

## Requirements

- **macOS 13.0** (Ventura) or later
- **Swift 5.9+** (only needed if building from source)
- A [Kalshi](https://kalshi.com) account with API access

## Installation

### Option 1: Homebrew

```bash
brew install --cask neelgun17/tap/predictbar
```

The app is ad-hoc signed (not notarized), so macOS still blocks the first launch. After installing, clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/PredictBar.app
```

Then launch it:

```bash
open /Applications/PredictBar.app
```

The icon will appear in your menu bar (PredictBar runs as a menu bar app, so there's no dock icon). Upgrade later with `brew upgrade --cask predictbar`.

### Option 2: Download from GitHub Releases

1. Go to the [Releases](https://github.com/neelgun17/PredictBar/releases) page and download the latest `PredictBar-vX.X.X.dmg`.
2. Double-click the DMG, then drag `PredictBar.app` into the `Applications` shortcut inside the window.
3. Open `/Applications/PredictBar.app`. The first launch will show **"PredictBar can't be opened because it is from an unidentified developer"** — close that dialog, **right-click the app → Open → Open**. macOS only requires this once per install.
4. The icon will appear in your menu bar.

#### Why the right-click step is necessary

Release builds are ad-hoc signed (not notarized with a paid Apple Developer ID), so Gatekeeper blocks the first launch. Right-clicking → Open whitelists the app permanently on your machine. Notifications may also be less reliable under ad-hoc signing — if you need them rock-solid, build from source and sign with your own Apple Developer certificate (see Option 3).

> A `PredictBar-vX.X.X.zip` is also published if you prefer that format. Zip downloads pick up a stricter quarantine flag that can produce a misleading "damaged" error; if you hit it, run `xattr -dr com.apple.quarantine /Applications/PredictBar.app` once. The DMG path avoids this.

### Option 3: Build from Source

1. **Clone the repository**:
   ```bash
   git clone https://github.com/neelgun17/PredictBar.git
   cd PredictBar
   ```

2. **Build and run**:
   ```bash
   make run
   ```

   Other useful commands:
   ```bash
   make help       # show all available targets
   make build      # debug build only
   make debug      # build and run the debug binary in the foreground
   make bundle     # create signed .app without launching
   ```

   To sign with your own Apple Developer certificate (required for notifications):
   ```bash
   CODESIGN_IDENTITY="Apple Development" make run
   ```

3. The icon will appear in your menu bar.

## Setup

### 1. Get Your API Keys

1. Log in to [Kalshi](https://kalshi.com)
2. Go to **Settings** > **API** in your account
3. Click **Generate New API Key**
4. You'll receive:
   - **API Key** (a UUID like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
   - **Private Key** (starts with `-----BEGIN RSA PRIVATE KEY-----`)
5. **Save both immediately** - the private key is only shown once!

### 2. Configure the App

1. Click the **PredictBar icon** in your menu bar
2. Click **Settings** (or press `Cmd + ,`)
3. Go to the **API** tab
4. Enter your **API Key** and **Private Key**
5. Click **Save Credentials**

Your portfolio will load automatically once credentials are saved.

> **Keychain prompt:** the first time PredictBar reads your saved credentials, macOS asks for permission to access the Keychain. Click **Always Allow** (not "Allow") — "Allow" only grants one-time access, so the prompt will keep reappearing. Because the app is ad-hoc signed, this prompt also returns once after each app update; choosing **Always Allow** each time is expected and safe.

## Usage

### Menu Bar
The menu bar displays your chosen metric (configurable in Settings > Display):
- **Cash Out Value** - What you'd get if you sold all positions now
- **ROI %** - Overall return on investment
- **P&L** - Total profit/loss in dollars
- **Portfolio Value** - Total value of positions
- **Balance** - Available cash balance

### Dropdown View
Click the menu bar icon to see:
- Portfolio summary (balance, portfolio value, total ROI)
- List of all active positions with:
  - Current price and your average entry price
  - Quantity held
  - Profit/Loss and ROI %
  - Quick sell button with current bid price
  - Alert configuration button

### Configuring Alerts

#### Global Alerts
1. Go to **Settings** > **Notifications**
2. Enable notifications
3. Set default **High ROI** and **Low ROI** thresholds

#### Per-Position Alerts
1. Click the **bell icon** next to any position
2. Configure custom thresholds for that position:
   - High/Low ROI alerts
   - Profit target (dollar amount)
   - Price target (sell when price reaches X)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "unidentified developer" on first launch | Expected for ad-hoc signed builds. Right-click the app → **Open** → **Open**. Required only once per install. |
| "PredictBar is damaged and can't be opened" | This appears with zip downloads (not DMG). Run `xattr -dr com.apple.quarantine /Applications/PredictBar.app` once, or re-download the DMG. |
| "Failed to decode Private Key" | Make sure you copied the entire key including `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----` |
| Repeated Keychain password prompts | Click **Always Allow**, not "Allow." "Allow" grants one-time access and the app re-reads the Keychain on every refresh, so the prompt loops. The prompt also reappears once after each app update (expected for ad-hoc signed builds). |
| Positions not loading | Check your internet connection. Try clicking Refresh in the dropdown. |
| App not appearing in menu bar | The app runs as a menu bar app only (no dock icon). Look for the icon in your menu bar. |

### View Logs
PredictBar logs through the macOS unified logging system (subsystem
`com.predictbar.app`), so the messages don't print to the terminal. Stream them
live with:
```bash
log stream --predicate 'subsystem == "com.predictbar.app"' --level debug
```
Or open **Console.app** and filter on `com.predictbar.app`. Use `make debug` to
run the debug build in the foreground.

## Privacy & Security

- **Credentials** are stored in the macOS Keychain, not in plain text files
- **No data** is sent to any servers other than the Kalshi API
- **No analytics** or tracking of any kind
- All communication uses **HTTPS**

## License

MIT License - see [LICENSE](LICENSE) for details.

## Disclaimer

This is an unofficial application and is not affiliated with, endorsed by, or connected to Kalshi in any way. Use at your own risk. Always verify important information directly on [Kalshi.com](https://kalshi.com).
