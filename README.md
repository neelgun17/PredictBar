# PredictBar

A native macOS menu bar application for tracking your prediction market portfolio, positions, and ROI in real-time.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

<!--
## Screenshots

Add screenshots here:
![Menu Bar](screenshots/menubar.png)
![Dropdown View](screenshots/dropdown.png)
![Settings](screenshots/settings.png)
-->

## Features

- **Real-time Portfolio Tracking** - View your total portfolio value, cash balance, and ROI directly in the menu bar
- **Position Management** - See all active positions with current price, profit/loss, ROI, and sparkline charts
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

### Option 1: Download from GitHub Releases (Recommended for most users)

1. Go to the [Releases](https://github.com/neelgun17/PredictBar/releases) page and download the latest `PredictBar-vX.X.X.zip`.
2. Unzip and drag `PredictBar.app` into your `/Applications` folder.
3. **Remove the macOS quarantine flag** (required on every install/update):
   ```bash
   xattr -dr com.apple.quarantine /Applications/PredictBar.app
   ```
4. Open the app. The icon will appear in your menu bar.

#### Why step 3 is necessary

Release builds are ad-hoc signed (not notarized with a paid Apple Developer ID), so macOS attaches a quarantine attribute to anything downloaded via browser. Without removing it, Gatekeeper will refuse to launch the app — often with **"PredictBar is damaged and can't be opened. Move it to the Trash."** This is not actually corruption.

If you'd rather avoid this step on every update — or you need reliable notifications (which may not fire under an ad-hoc signature) — build from source and sign with your own Apple Developer certificate (see Option 2).

### Option 2: Build from Source

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
   make debug      # build and run with console output
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
| "PredictBar is damaged and can't be opened" / "unidentified developer" | macOS quarantined the downloaded app. Run `xattr -dr com.apple.quarantine /Applications/PredictBar.app` and try again. |
| "Failed to decode Private Key" | Make sure you copied the entire key including `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----` |
| Positions not loading | Check your internet connection. Try clicking Refresh in the dropdown. |
| App not appearing in menu bar | The app runs as a menu bar app only (no dock icon). Look for the icon in your menu bar. |

### View Logs
To see detailed logs for debugging:
```bash
make debug
```

## Privacy & Security

- **Credentials** are stored in the macOS Keychain, not in plain text files
- **No data** is sent to any servers other than the Kalshi API
- **No analytics** or tracking of any kind
- All communication uses **HTTPS**

## License

MIT License - see [LICENSE](LICENSE) for details.

## Disclaimer

This is an unofficial application and is not affiliated with, endorsed by, or connected to Kalshi in any way. Use at your own risk. Always verify important information directly on [Kalshi.com](https://kalshi.com).
