# Kalshi Menu Bar 🚀

A native macOS menu bar application for tracking your Kalshi portfolio, positions, and ROI in real-time.

## Features

- **Real-time Updates**: View your total portfolio value and account balance directly in the menu bar.
- **Position Tracking**: See all your active positions, including current price, profit/loss, and ROI.
- **Smart Alerts**: Get notified when your positions hit high or low ROI thresholds.
- **Secure**: Your API credentials are stored securely in the macOS Keychain.
- **Native Experience**: Designed to look and feel like a part of macOS.

## Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/neelgun17/KalshiMenuBar.git
    cd KalshiMenuBar
    ```

2.  **Build and Run**:
    We've included a helper script to build and launch the app:
    ```bash
    ./restart.sh
    ```
    This will compile the app and launch it. You should see the Kalshi icon appear in your menu bar.

## Setup & Configuration

### 1. Get your Kalshi API Keys
To use this app, you need a Kalshi API Key and a Private Key.

1.  Log in to [Kalshi](https://kalshi.com).
2.  Go to the **API** section in your account settings.
3.  Generate a new API Key.
4.  **Important**: You will be given a **Key ID** (UUID) and a **Private Key** (a long text block starting with `-----BEGIN RSA PRIVATE KEY-----`).
5.  Copy both of these.

### 2. Configure the App
1.  Click the **Kalshi icon** in your menu bar.
2.  Select **Settings** (or press `Cmd+,`).
3.  Navigate to the **API** tab.
4.  Paste your **API Key** (UUID) into the first field.
5.  Paste your **Private Key** (PEM format) into the second field.
    *   *Note: The app accepts the key with or without the header/footer lines.*
6.  Click **Save Credentials**.

Once saved, the app will immediately fetch your portfolio data.

## Usage

- **Menu Bar**: Shows your current Portfolio Value or Cash Out Value (configurable).
- **Dropdown**: Click the icon to see a detailed list of your active positions.
- **Refresh**: The app auto-refreshes, but you can force a refresh by clicking "Refresh" in the dropdown.
- **Quit**: To close the app, click "Quit" in the dropdown.

## Troubleshooting

- **"Failed to decode Private Key"**: Ensure you copied the entire Private Key, including the `-----BEGIN...` and `-----END...` lines.
- **Positions not showing**: Check your internet connection. If you just saved credentials, give it a moment to refresh.
- **Logs**: To view debug logs, run the app from the terminal:
    ```bash
    ./KalshiMenuBar.app/Contents/MacOS/KalshiMenuBar
    ```
