import Foundation

/// Classified user input for the watchlist add flow: either a raw ticker
/// (market or event — indistinguishable lexically, resolved via the API),
/// a kalshi.com URL reduced to its event/series tickers, or invalid input
/// with a user-facing reason.
enum WatchlistInput: Equatable {
    case marketOrEventTicker(String)
    case url(seriesTicker: String?, eventTicker: String?)
    case invalid(String)
}

/// Parses the watchlist "add market" input. Pure and side-effect free so it is
/// unit-testable. URL handling is the inverse of `DashboardViewModel.kalshiMarketURL`,
/// which builds `kalshi.com/markets/{series}/{slug}/{event}` links.
enum WatchlistInputParser {
    private static let tickerCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    /// Uppercase alphanumeric plus `.`/`_`/`-`, starting with a letter or digit
    /// (Kalshi tickers include dots, e.g. INXD-23DEC29-T4575.99).
    private static func isValidTicker(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else { return false }
        return s.unicodeScalars.allSatisfy { tickerCharacters.contains($0) }
    }

    static func parse(_ raw: String) -> WatchlistInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid("Enter a Kalshi market URL or ticker.")
        }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            || trimmed.lowercased().hasPrefix("kalshi.com/") || trimmed.lowercased().hasPrefix("www.kalshi.com/") {
            return parseURL(trimmed)
        }

        let ticker = trimmed.uppercased()
        guard isValidTicker(ticker) else {
            return .invalid("Enter a Kalshi market URL or ticker.")
        }
        return .marketOrEventTicker(ticker)
    }

    private static func parseURL(_ raw: String) -> WatchlistInput {
        // Tolerate URLs pasted without a scheme (kalshi.com/...)
        let normalized = raw.lowercased().hasPrefix("http") ? raw : "https://" + raw
        guard let components = URLComponents(string: normalized),
              let host = components.host?.lowercased(),
              host == "kalshi.com" || host.hasSuffix(".kalshi.com") else {
            return .invalid("Only kalshi.com URLs are supported.")
        }

        // Explicit ticker in query params wins (e.g. ?market=KXBTC-...)
        if let items = components.queryItems {
            for name in ["market", "ticker", "market_ticker"] {
                if let value = items.first(where: { $0.name == name })?.value,
                   !value.isEmpty,
                   isValidTicker(value.uppercased()) {
                    return .marketOrEventTicker(value.uppercased())
                }
            }
        }

        // Path shapes built by the app (and used by kalshi.com):
        //   /markets/{series}/{slug}/{event} -> event ticker
        //   /markets/{series}/{slug}         -> series ticker
        //   /markets/{series}                -> series ticker
        // Also accept /events/{event} just in case.
        let parts = components.path.split(separator: "/").map(String.init)
        guard let rootIndex = parts.firstIndex(where: { $0 == "markets" || $0 == "events" }) else {
            return .invalid("Couldn't find a market in that URL.")
        }
        let root = parts[rootIndex]
        let rest = Array(parts.dropFirst(rootIndex + 1))
        guard !rest.isEmpty else {
            return .invalid("Couldn't find a market in that URL.")
        }

        if root == "events" {
            return .url(seriesTicker: nil, eventTicker: rest[0].uppercased())
        }

        switch rest.count {
        case 1:
            return .url(seriesTicker: rest[0].uppercased(), eventTicker: nil)
        case 2:
            return .url(seriesTicker: rest[0].uppercased(), eventTicker: nil)
        default:
            return .url(seriesTicker: rest[0].uppercased(), eventTicker: rest[2].uppercased())
        }
    }
}
