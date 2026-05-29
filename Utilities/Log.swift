import Foundation
import os

/// Centralized unified-logging facade. Replaces ad-hoc `print()` calls so
/// diagnostics land in the unified logging system — visible in Console.app or via
/// `log stream --predicate 'subsystem == "com.predictbar.app"'` — instead of
/// stdout. This keeps release builds free of console noise while preserving
/// greppable, categorized diagnostics. Dynamic values are marked `.public` only
/// where they are non-sensitive (errors, counts, hosts); credentials are never
/// interpolated.
enum Log {
    private static let subsystem = "com.predictbar.app"

    static let app         = Logger(subsystem: subsystem, category: "app")
    static let network     = Logger(subsystem: subsystem, category: "network")
    static let websocket   = Logger(subsystem: subsystem, category: "websocket")
    static let tls         = Logger(subsystem: subsystem, category: "tls")
    static let credentials = Logger(subsystem: subsystem, category: "credentials")
    static let crypto      = Logger(subsystem: subsystem, category: "crypto")
    static let alerts      = Logger(subsystem: subsystem, category: "alerts")
}
