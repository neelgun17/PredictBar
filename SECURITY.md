# Security Policy

## Reporting a Vulnerability

This application handles financial API credentials (Kalshi API keys and RSA private keys). If you discover a security vulnerability, **please do not open a public issue**.

Instead, report it privately:
- Email: [open an issue marked "security"](https://github.com/neelgun17/KalshiMenuBar/issues) with the title **[SECURITY]** and minimal details, then share the full report privately via the contact method provided in the response.

## Scope

The following are in scope:
- Credential leakage (Keychain bypass, logging secrets, writing keys to disk)
- Code injection or command injection via API responses
- Man-in-the-middle vulnerabilities in API communication
- Signature bypass in the RSA-SHA256 authentication flow

## Design Principles

- Credentials are stored exclusively in the macOS Keychain.
- No secrets are logged, written to UserDefaults, or stored in plaintext.
- All API communication uses HTTPS.
- Every API request is signed with RSA-SHA256.
