import Foundation
import Security
import CryptoKit

/// Provides a `URLSession` configured with SPKI (Subject Public Key Info) pinning
/// for Kalshi API hosts.
///
/// We pin the **Amazon intermediate CA** SPKI rather than the leaf certificate.
/// AWS Certificate Manager rotates leaf certs every ~90 days, but the intermediate
/// is stable for years. The Amazon Root CA 1 SPKI is also accepted as a backup pin
/// in case the intermediate is rotated (rare but possible).
///
/// **What pinning protects against:** A user installing a malicious root CA on their
/// Mac (corporate MITM proxy, malware that adds a CA, compromised public CA) can
/// otherwise generate a forged cert for `api.elections.kalshi.com` that the system
/// trust store accepts. Pinning rejects any cert whose chain doesn't include one of
/// these specific public keys.
///
/// **What it does NOT protect against:** Compromise of Amazon's intermediate CA itself.
final class PinnedURLSession: NSObject {
    static let shared = PinnedURLSession()

    /// Hosts we apply pinning to. Other hosts fall through to system trust.
    /// (Currently the app only talks to Kalshi, but this is a defense-in-depth boundary.)
    private static let pinnedHosts: Set<String> = [
        "api.elections.kalshi.com"
    ]

    /// Base64-encoded SHA-256 hashes of accepted SPKI DERs.
    /// Run `Scripts/print_kalshi_spki.sh` to refresh these values.
    private static let pinnedSPKIHashes: Set<String> = [
        // Amazon RSA 2048 M02 (intermediate)
        "18tkPyr2nckv4fgo0dhAkaUtJ2hu2831xlO2SKhq8dg=",
        // Amazon Root CA 1 (backup)
        "++MBgDH5WGvL9Bcn5Be30cRcL0f5O+NyoXuWtQdX1aI="
    ]

    /// Public session used for all Kalshi REST calls.
    let session: URLSession

    /// Public session for WebSocket connections.
    let webSocketSession: URLSession

    private override init() {
        let delegate = PinningDelegate()
        self.session = URLSession(configuration: Self.makeBaseConfig(), delegate: delegate, delegateQueue: nil)
        self.webSocketSession = URLSession(configuration: Self.makeBaseConfig(), delegate: delegate, delegateQueue: nil)

        super.init()
        delegate.owner = self
    }

    /// Shared hardened defaults for both REST and WebSocket sessions.
    private static func makeBaseConfig() -> URLSessionConfiguration {
        let cfg = URLSessionConfiguration.default
        cfg.tlsMinimumSupportedProtocolVersion = .TLSv12
        cfg.httpAdditionalHeaders = nil
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return cfg
    }

    fileprivate func validateServerTrust(_ trust: SecTrust, host: String) -> Bool {
        // Only enforce pinning for hosts we explicitly pin
        guard Self.pinnedHosts.contains(host.lowercased()) else { return true }

        // First, require the chain to validate against the system trust store.
        // This ensures revocation, expiry, hostname, etc. are still checked.
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            Log.tls.error("System trust evaluation failed for \(host, privacy: .public): \(error.map { CFErrorCopyDescription($0) as String } ?? "unknown", privacy: .public)")
            return false
        }

        // Then walk the chain and look for any cert whose SPKI hash matches a pin.
        let count = SecTrustGetCertificateCount(trust)
        for i in 0..<count {
            guard let cert = SecTrustGetCertificateAtIndex(trust, i) else { continue }
            guard let publicKey = SecCertificateCopyKey(cert),
                  let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
            else { continue }

            // The hardcoded SPKI prefix below is only valid for 2048-bit RSA keys.
            // If a cert in the chain uses a different key type/size, the reconstructed
            // SPKI won't match anything in the pin set — fail loudly so we notice
            // during cert rotation rather than silently rejecting every connection.
            guard let attrs = SecKeyCopyAttributes(publicKey) as? [String: Any],
                  let keyType = attrs[kSecAttrKeyType as String] as? String,
                  keyType == (kSecAttrKeyTypeRSA as String),
                  let keyBits = attrs[kSecAttrKeySizeInBits as String] as? Int,
                  keyBits == 2048
            else {
                Log.tls.warning("Chain cert \(i) is not RSA-2048; pin verification cannot be performed. Update spkiDER() in PinnedURLSession.swift to support the new key type.")
                continue
            }

            // SecKeyCopyExternalRepresentation returns raw key bytes for RSA, not the
            // full SubjectPublicKeyInfo DER. Wrap with the standard RSA-2048 SPKI header
            // so the hash matches the output of `openssl x509 -pubkey | openssl pkey -pubin -outform DER`.
            let spkiDER = Self.spkiDER(forRSAPublicKey: publicKeyData)
            let hash = Data(SHA256.hash(data: spkiDER)).base64EncodedString()
            if Self.pinnedSPKIHashes.contains(hash) {
                return true
            }
        }

        Log.tls.error("Certificate pinning failed for \(host, privacy: .public) — no SPKI in chain matched any pin.")
        return false
    }

    /// Prepends the ASN.1 SubjectPublicKeyInfo header for a 2048-bit RSA key
    /// so that `SHA256(spkiDER)` matches the canonical SPKI hash used by openssl.
    private static func spkiDER(forRSAPublicKey rawKey: Data) -> Data {
        // ASN.1 DER prefix for a 2048-bit RSA SubjectPublicKeyInfo.
        // This is the same prefix HPKP/RFC 7469 implementations use.
        let rsa2048SPKIHeader: [UInt8] = [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ]
        var spki = Data(rsa2048SPKIHeader)
        spki.append(rawKey)
        return spki
    }
}

private final class PinningDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionWebSocketDelegate {
    weak var owner: PinnedURLSession?

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        if owner?.validateServerTrust(trust, host: host) == true {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
