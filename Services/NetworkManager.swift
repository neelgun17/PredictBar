import Foundation
import Security

class NetworkManager {
    static let shared = NetworkManager()
    private let baseURL = URL(string: "https://api.elections.kalshi.com/trade-api/v2")!
    
    private init() {}
    
    func fetchPortfolio(completion: @escaping (Result<[Position], Error>) -> Void) {
        guard let request = authenticatedRequest(to: "/portfolio/positions") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            do {
                struct PortfolioResponse: Decodable {
                    let marketPositions: [Position]
                }
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                let decodedResponse = try decoder.decode(PortfolioResponse.self, from: data)
                completion(.success(decodedResponse.marketPositions))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    struct BalanceResponse: Decodable {
        let balance: Int
        let portfolioValue: Int
    }

    func fetchBalance(completion: @escaping (Result<BalanceResponse, Error>) -> Void) {
        guard let request = authenticatedRequest(to: "/portfolio/balance") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(BalanceResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    struct MarketResponse: Decodable {
        let market: Market
    }

    struct Market: Decodable {
        let ticker: String
        let eventTicker: String
        let title: String
        let subtitle: String?
        let lastPrice: Int?
        let yesBid: Int?
        let noBid: Int?
        let yesAsk: Int?
        let noAsk: Int?
        
        enum CodingKeys: String, CodingKey {
            case ticker
            case eventTicker = "event_ticker"
            case title
            case subtitle
            case lastPrice = "last_price"
            case yesBid = "yes_bid"
            case noBid = "no_bid"
            case yesAsk = "yes_ask"
            case noAsk = "no_ask"
        }
    }

    func fetchMarket(ticker: String, completion: @escaping (Result<Market, Error>) -> Void) {
        guard let request = authenticatedRequest(to: "/markets/\(ticker)") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            do {
                // Debug: Print market response
                if let jsonStr = String(data: data, encoding: .utf8) {
                     // print("Market Response for \(ticker): \(jsonStr)")
                }
                
                let response = try JSONDecoder().decode(MarketResponse.self, from: data)
                completion(.success(response.market))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    struct EventResponse: Decodable {
        let event: Event
    }
    
    struct Event: Decodable {
        let eventTicker: String
        let seriesTicker: String
        let subTitle: String?
        let title: String
        
        enum CodingKeys: String, CodingKey {
            case eventTicker
            case seriesTicker
            case subTitle
            case title
        }
    }
    
    func fetchEvent(eventTicker: String, completion: @escaping (Result<Event, Error>) -> Void) {
        guard let request = authenticatedRequest(to: "/events/\(eventTicker)") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            do {
                // Debug: Print event response
                if let jsonStr = String(data: data, encoding: .utf8) {
                     // print("Event Response for \(eventTicker): \(jsonStr)")
                }
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(EventResponse.self, from: data)
                completion(.success(response.event))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    struct SeriesResponse: Decodable {
        let series: Series
    }
    
    struct Series: Decodable {
        let ticker: String
        let title: String
        // We hope the slug is here, maybe as 'url_slug' or derived from title?
        // Let's inspect the raw JSON first.
    }
    
    func fetchSeries(seriesTicker: String, completion: @escaping (Result<Series, Error>) -> Void) {
        guard let request = authenticatedRequest(to: "/series/\(seriesTicker)") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            do {
                // Debug: Print series response
                // if let jsonStr = String(data: data, encoding: .utf8) {
                //      print("Series Response for \(seriesTicker): \(jsonStr)")
                // }
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(SeriesResponse.self, from: data)
                completion(.success(response.series))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // Helper for authenticated requests
    private func authenticatedRequest(to endpoint: String) -> URLRequest? {
        guard let url = URL(string: "https://api.elections.kalshi.com/trade-api/v2" + endpoint) else { return nil }
        
        print("DEBUG: Requesting URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        let path = "/trade-api/v2" + endpoint
        
        let messageToSign = timestamp + method + path
        
        guard let signature = sign(message: messageToSign, privateKeyPEM: Secrets.privateKey) else {
            return nil
        }
        
        request.addValue(Secrets.keyId, forHTTPHeaderField: "KALSHI-ACCESS-KEY")
        request.addValue(timestamp, forHTTPHeaderField: "KALSHI-ACCESS-TIMESTAMP")
        request.addValue(signature, forHTTPHeaderField: "KALSHI-ACCESS-SIGNATURE")
        
        return request
    }
    
    private func sign(message: String, privateKeyPEM: String) -> String? {
        guard let data = message.data(using: .utf8) else { return nil }
        
        // 1. Clean PEM string
        let cleanPEM = privateKeyPEM
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let keyData = Data(base64Encoded: cleanPEM) else {
            return nil
        }
        
        // 2. Create SecKey
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            return nil
        }
        
        // 3. Sign with RSA-PSS-SHA256
        let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePSSSHA256
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            return nil
        }
        
        guard let signatureData = SecKeyCreateSignature(privateKey, algorithm, data as CFData, &error) else {
            return nil
        }
        
        return (signatureData as Data).base64EncodedString()
    }
    
    struct CandlestickResponse: Decodable {
        let ticker: String?
        let candlesticks: [Candlestick]
    }
    
    struct Candlestick: Decodable {
        let endPeriodTs: Int?
        let yesBid: PriceWindow?
        let yesAsk: PriceWindow?
        let price: PriceWindow?
        let yesPrice: PriceWindow?
        let midPrice: PriceWindow?
    }
    
    struct PriceWindow: Decodable {
        let open: Int?
        let high: Int?
        let low: Int?
        let close: Int?
        let openDollars: String?
        let highDollars: String?
        let lowDollars: String?
        let closeDollars: String?
    }
    
    /// Fetch market history using the documented series endpoint only (1m candles).
    func fetchMarketHistory(seriesTicker: String?, marketTicker: String, completion: @escaping (Result<[Double], Error>) -> Void) {
        func parsePrices(data: Data) throws -> [Double] {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(CandlestickResponse.self, from: data)
            
            let sorted = response.candlesticks.sorted { (lhs, rhs) in
                (lhs.endPeriodTs ?? 0) < (rhs.endPeriodTs ?? 0)
            }
            
            var lastMid: Double?
            
            let prices = sorted.compactMap { candle -> Double? in
                if let midPrice = candle.midPrice?.close {
                    let mid = Double(midPrice) / 100.0
                    lastMid = mid
                    return mid
                }
                
                if let trade = candle.price?.close ?? candle.yesPrice?.close {
                    let last = Double(trade) / 100.0
                    lastMid = last
                    return last
                }
                
                let bidClose = candle.yesBid?.close
                let askClose = candle.yesAsk?.close
                
                if let bid = bidClose, let ask = askClose {
                    let mid = Double(bid + ask) / 200.0
                    lastMid = mid
                    return mid
                }
                
                if let bid = bidClose {
                    let mid = Double(bid) / 100.0
                    lastMid = mid
                    return mid
                }
                
                if let ask = askClose {
                    let mid = Double(ask) / 100.0
                    lastMid = mid
                    return mid
                }
                
                if let dollars = candle.yesBid?.closeDollars, let value = Double(dollars) {
                    lastMid = value
                    return value
                }
                
                if let dollars = candle.yesAsk?.closeDollars, let value = Double(dollars) {
                    lastMid = value
                    return value
                }
                
                return lastMid
            }
            
            return prices
        }
        
        func logResponse(_ label: String, _ data: Data?, _ response: URLResponse?, _ error: Error?) {
            if let error = error {
                print("Candles \(label) error: \(error)")
                return
            }
            guard let http = response as? HTTPURLResponse else { print("Candles \(label) missing HTTP response"); return }
            print("Candles \(label) status: \(http.statusCode)")
            if let data = data, let body = String(data: data, encoding: .utf8) {
                print("Candles \(label) body: \(body.prefix(200))")
            }
        }
        
        func makeSeriesRequest(start: Int, end: Int) -> URLRequest? {
            guard let series = seriesTicker else { return nil }
            var components = URLComponents(string: "/series/\(series)/markets/\(marketTicker)/candlesticks")
            components?.queryItems = [
                URLQueryItem(name: "start_ts", value: String(start)),
                URLQueryItem(name: "end_ts", value: String(end)),
                URLQueryItem(name: "period_interval", value: "1")
            ]
            guard let endpoint = components?.string else { return nil }
            return authenticatedRequest(to: endpoint)
        }
        
        func runRequest(_ request: URLRequest, label: String, onResult: @escaping (Result<[Double], Error>) -> Void) {
            URLSession.shared.dataTask(with: request) { data, response, error in
                guard let http = response as? HTTPURLResponse else {
                    logResponse(label, data, response, error)
                    onResult(.failure(URLError(.badServerResponse)))
                    return
                }
                
                if !(200...299).contains(http.statusCode) {
                    logResponse(label, data, response, error)
                    onResult(.failure(URLError(.badServerResponse)))
                    return
                }
                
                guard let data = data else {
                    logResponse(label, data, response, error)
                    onResult(.failure(URLError(.badServerResponse)))
                    return
                }
                
                do {
                    let prices = try parsePrices(data: data)
                    if prices.isEmpty {
                        print("Candles \(label) empty prices")
                        onResult(.failure(URLError(.cannotParseResponse)))
                    } else {
                        onResult(.success(prices))
                    }
                } catch {
                    print("Candles \(label) decode error: \(error)")
                    onResult(.failure(error))
                }
            }.resume()
        }
        
        // Try current 24h window, then a 24h window ending 24h ago (helps if local clock is skewed)
        let now = Int(Date().timeIntervalSince1970)
        let windows = [
            (start: now - 24 * 60 * 60, end: now),
            (start: now - 48 * 60 * 60, end: now - 24 * 60 * 60)
        ]
        
        guard let seriesTicker = seriesTicker else {
            print("Candles missing series ticker for \(marketTicker)")
            completion(.failure(URLError(.badURL)))
            return
        }
        
        func attemptWindow(index: Int) {
            guard index < windows.count else {
                completion(.failure(URLError(.cannotFindHost)))
                return
            }
            
            let window = windows[index]
            guard let seriesReq = makeSeriesRequest(start: window.start, end: window.end) else {
                completion(.failure(URLError(.badURL)))
                return
            }
            
            print("Candles series URL: \(seriesReq.url?.absoluteString ?? "nil")")
            runRequest(seriesReq, label: "series \(seriesReq.url?.absoluteString ?? "")") { result in
                switch result {
                case .success(let prices):
                    completion(.success(prices))
                case .failure:
                    // Try next window
                    attemptWindow(index: index + 1)
                }
            }
        }
        
        attemptWindow(index: 0)
    }
}
