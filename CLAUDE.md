# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Platform Requirements

- **macOS 13.0+** (Ventura), **Swift 5.9+** (swift-tools-version: 5.9)
- SPM for main app build

## Build & Run Commands

### Development
```bash
# Build debug version
swift build

# Run debug binary (with console output)
.build/debug/PredictBar

# Full rebuild + app bundle + code signing + launch
./restart.sh
```

`restart.sh` does: clean build → create .app bundle → codesign with developer cert → `open PredictBar.app`. Notifications require running as a signed .app bundle.

### Production Build
```bash
swift build -c release
# Binary at .build/release/PredictBar
```

### Xcode Build (compilation verification)
```bash
xcodebuild -scheme PredictBar -configuration Debug -destination 'platform=macOS' clean build
```

## Architecture Overview

### Application Type
This is a **macOS menu bar application** (LSUIElement = true, no dock icon) that displays prediction market trading positions in the menu bar with a dropdown interface.

### Core Components

#### 1. Data Flow Architecture
```
User → MenuBar Icon → DropdownView
                ↓
        DashboardViewModel (central state)
                ↓
        ┌───────┴───────┐
        ↓               ↓
   NetworkManager   WebSocketManager
   (REST API)      (Real-time prices)
        ↓               ↓
   Kalshi API (/portfolio, /balance, /markets)
```

**DashboardViewModel** is the central source of truth for:
- Position data (quantities, prices, P&L)
- Portfolio metrics (ROI, cash out value, balance)
- Alert state management
- Real-time price updates via WebSocket subscriptions

#### 2. Alert System Architecture

The alert system uses **state-based transitions** with hysteresis to prevent notification spam:

**Alert Types:**
1. **High/Low ROI** - State-based with 3% hysteresis buffer (e.g., 20% threshold triggers at 23%, resets at 17%)
2. **Target Profit** - One-time trigger when P&L reaches dollar goal
3. **Target Price** - One-time trigger when position price reaches target
4. **Stop-Loss** - Triggers once when price/profit drops below threshold, resets on recovery + 3% buffer
5. **Arbitrage** - Detects hedge opportunities with guaranteed profit (5-min cooldown + $1 profit increase requirement)

**Alert State Tracking** (`PositionAlertState` in DashboardViewModel.swift):
- `roiState`: Tracks state transitions (low/neutral/high) for hysteresis
- `stopLossTriggered`: Boolean flag to prevent duplicate stop-loss alerts
- Time-based deduplication: 5-minute cooldowns on repeated alerts
- State persistence: Saved to UserDefaults, survives app restarts

**Alert Configuration** (`AlertSettings` in SettingsViewModel.swift):
- Global thresholds: Default ROI % thresholds for all positions
- Per-position overrides: Custom thresholds, target profit/price, stop-loss settings
- Dictionary storage: `[ticker: AlertSettings]` persisted to UserDefaults

**Alert Flow:**
```
checkThresholds() (every 30s + on settings change)
    → handleAlerts(for: position)          // ROI + targets
    → checkArbitrageOpportunity()          // Hedge detection
    → checkStopLoss()                      // Downside protection
    → queueAlert()                         // Add to pending queue
    → scheduleGroupedNotification()        // 2-second batching
    → sendNotification()                   // macOS notification center
```

#### 3. Price Update System

**WebSocket Integration:**
- Live ticker quotes via `wss://api.elections.kalshi.com/trade-api/ws/v2`
- Authentication: KALSHI-ACCESS-KEY header + RSA-SHA256 signature
- Subscribe/unsubscribe to tickers dynamically based on open positions
- Auto-reconnect on disconnection with 5-second delay
- 10-second ping/pong keep-alive

**Price Calculation** (Position.swift):
- `currentPrice`: Executable sell price based on position side (yesBid for Yes, noAsk for No)
- `realizedPnL`: Net profit after 7% commission (rounded to nearest cent)
- `realizedROI`: ROI calculation includes commission deduction
- Commission formula: `0.07 × contracts × sellPrice × (1 - sellPrice)`

#### 4. Authentication & Security

**API Authentication** (NetworkManager.swift + WebSocketManager.swift):
- Credentials stored in macOS Keychain via `CredentialsManager`
- Every API request signed with RSA-SHA256:
  ```
  signature = sign(timestamp + method + path [+ body])
  Headers: KALSHI-ACCESS-KEY, KALSHI-ACCESS-SIGNATURE, KALSHI-ACCESS-TIMESTAMP
  ```
- Private key format: PEM-encoded RSA key (-----BEGIN RSA PRIVATE KEY-----)
- Decoding: Uses SecKeyCreateWithData with kSecAttrKeyTypeRSA

**Security Notes:**
- Never commit API keys or private keys
- Credentials accessed only through CredentialsManager.shared.get()
- UserDefaults used only for non-sensitive settings (thresholds, UI preferences)

### Key Files by Function

**State Management:**
- `ViewModels/DashboardViewModel.swift` - Main app state, position tracking, alerts
- `ViewModels/SettingsViewModel.swift` - User preferences, alert settings (Singleton)

**Networking:**
- `Services/NetworkManager.swift` - REST API client for portfolio/balance/market data
- `Services/WebSocketManager.swift` - Real-time price updates via WebSocket
- `Services/CredentialsManager.swift` - Keychain operations for API credentials
- `Utilities/CryptoUtils.swift` - RSA signature generation for API authentication

**UI Components:**
- `Views/DropdownView.swift` - Main dropdown showing positions list
- `Views/MenuBarIconView.swift` - Menu bar icon with dynamic text
- `Views/Settings/PositionAlertConfigurationView.swift` - Per-position alert config popup
- `Views/Settings/NotificationSettingsView.swift` - Global alert settings

**Data Models:**
- `Models/Position.swift` - Position data, P&L calculations, arbitrage detection
- `Models/Market.swift` - Market metadata from API
- `Models/UserBalance.swift` - Account balance data

## Important Patterns & Conventions

### When Adding New Alert Types

1. Add case to `AlertType` enum in DashboardViewModel.swift (with emoji)
2. Add state tracking fields to `PositionAlertState` struct (if needed)
3. Add configuration fields to `AlertSettings` struct in SettingsViewModel.swift
4. Implement detection method (e.g., `checkStopLoss()`) following existing patterns:
   - Check thresholds
   - Apply deduplication (time-based or state-based)
   - Use `queueAlert()` to add to notification queue
   - Update state with `positionAlertStates[ticker] = state`
5. Call detection method in `checkThresholds()` loop
6. Add UI controls in `PositionAlertConfigurationView.swift`

### P&L and ROI Calculations

**Critical:** Always account for 7% commission on sells:
- Use `position.realizedPnL` and `position.realizedROI` (includes commission)
- Never calculate P&L directly from `currentPrice × quantity - cost`
- Commission is rounded to nearest cent per API behavior

### WebSocket Ticker Subscription

When positions change:
1. Extract unique tickers from positions array
2. Call `WebSocketManager.shared.subscribeToTickers([tickers])`
3. Manager auto-unsubscribes from removed tickers
4. Price updates arrive via `priceUpdate` Combine publisher

### State Persistence

- Alert states: `positionAlertStates` → UserDefaults (JSON-encoded)
- Alert settings: `alertSettings` → UserDefaults (per-position overrides)
- User preferences: Published properties in SettingsViewModel with didSet → UserDefaults
- Credentials: macOS Keychain only (never UserDefaults)

## Testing & Debugging

### View Logs
```bash
# Run with console output visible
.build/debug/PredictBar

# Or use debug script
./debug_run.sh  # outputs to debug_output.txt
```

### Common Debugging Scenarios

**Alerts not firing:**
- Check `SettingsViewModel.shared.notificationsEnabled`
- Verify position has alerts enabled: `alertSettings[ticker].isEnabled`
- Check state: `positionAlertStates[ticker]` for trigger flags
- Verify threshold crossings with 3% hysteresis buffer

**Price not updating:**
- Check `WebSocketManager.shared.isConnected` in UI
- Verify ticker is in `subscribedTickers` array
- Look for WebSocket errors in console (authentication, reconnection)

**API errors:**
- Verify credentials with `try? CredentialsManager.shared.get()`
- Check timestamp is current (within 60s)
- Ensure private key includes header/footer lines
- Test signature generation in CryptoUtils.swift

### Manual Testing Alerts

To test alerts without waiting for market moves:
1. Set aggressive thresholds (e.g., High ROI = 1%, Low ROI = -1%)
2. Wait for next 30-second check cycle
3. Check console for "🔔 Alert queued" messages
4. Verify macOS notifications appear (check System Settings → Notifications)

## API Integration Notes

**Kalshi API Base URL:** `https://api.elections.kalshi.com/trade-api/v2`

**Key Endpoints Used:**
- `GET /portfolio/positions` - All open positions with market exposure
- `GET /portfolio/balance` - Cash balance + portfolio value
- `GET /markets/{ticker}` - Market metadata (title, subtitle, URL)

**WebSocket URL:** `wss://api.elections.kalshi.com/trade-api/ws/v2`

**Rate Limits:** Not enforced in code, but API may throttle. WebSocket preferred for price updates.

## Code Style Notes

- Use `@MainActor` for ViewModels that publish UI state
- Prefer `[weak self]` in closures to prevent retain cycles
- Network callbacks should dispatch to `DispatchQueue.main.async` for UI updates
- Use Combine publishers for reactive state updates (e.g., WebSocket → ViewModel)
- SwiftUI views should observe ViewModels via `@ObservedObject` or `@StateObject`
