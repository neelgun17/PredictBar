import AppKit
import Foundation

/// Opens a URL only if it points at kalshi.com over HTTPS. Market metadata
/// (tickers, titles, slugs) comes from the API; this guards against the API
/// being able to redirect the user's browser to an arbitrary host.
@discardableResult
func safeOpenKalshi(_ url: URL?) -> Bool {
    guard let url = url,
          url.scheme == "https",
          let host = url.host?.lowercased(),
          host == "kalshi.com" || host.hasSuffix(".kalshi.com")
    else { return false }
    NSWorkspace.shared.open(url)
    return true
}
