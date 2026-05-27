import Foundation
import Security

enum APIError: LocalizedError {
    case unauthorized(String?)
    case forbidden(String?)
    case server(status: Int, message: String?)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized(let msg):
            return msg.map { "Authentication failed: \($0)" } ?? "Authentication failed. Check your API key and private key in Settings."
        case .forbidden(let msg):
            return msg.map { "Access denied: \($0)" } ?? "Access denied. The API key may not have the required permissions."
        case .server(let status, let msg):
            return msg.map { "Kalshi API error (\(status)): \($0)" } ?? "Kalshi API returned an error (HTTP \(status))."
        case .unexpectedResponse:
            return "Unexpected response from Kalshi."
        }
    }
}

private struct KalshiErrorBody: Decodable {
    struct Inner: Decodable { let code: String?; let message: String? }
    let error: Inner?
}

private func apiError(for status: Int, body: Data) -> APIError {
    let message = (try? JSONDecoder().decode(KalshiErrorBody.self, from: body))?.error?.message
    switch status {
    case 401: return .unauthorized(message)
    case 403: return .forbidden(message)
    default:  return .server(status: status, message: message)
    }
}

class NetworkManager {
    static let shared = NetworkManager()
    private let baseURL = URL(string: "https://api.elections.kalshi.com/trade-api/v2")!

    private init() {}
    
    func fetchPortfolio(completion: @escaping (Result<[Position], Error>) -> Void) {
        guard let request = authenticatedRequest(to: "/portfolio/positions") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(apiError(for: http.statusCode, body: data)))
                return
            }

            do {
                struct PortfolioResponse: Decodable {
                    let marketPositions: [Position]?
                }

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase

                let decodedResponse = try decoder.decode(PortfolioResponse.self, from: data)
                completion(.success(decodedResponse.marketPositions ?? []))
            } catch {
                try? data.write(to: URL(fileURLWithPath: "/tmp/predictbar-last-portfolio.json"))
                NSLog("[PredictBar] fetchPortfolio decode failed: \(error). Full body written to /tmp/predictbar-last-portfolio.json")
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
        
        PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(apiError(for: http.statusCode, body: data)))
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decoded = try decoder.decode(BalanceResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                let bodyPreview = String(data: data.prefix(4000), encoding: .utf8) ?? "<non-utf8>"
                NSLog("[PredictBar] fetchBalance decode failed: \(error). Body preview: \(bodyPreview)")
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
        let status: String?
        let seriesTicker: String?
        
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
            case status
            case seriesTicker = "series_ticker"
        }
    }

    func fetchMarket(ticker: String, completion: @escaping (Result<Market, Error>) -> Void) {
        guard let request = authenticatedRequest(to: "/markets/\(ticker)") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(MarketResponse.self, from: data)
                completion(.success(response.market))
            } catch {
                try? data.write(to: URL(fileURLWithPath: "/tmp/predictbar-last-market-\(ticker).json"))
                NSLog("[PredictBar] fetchMarket(\(ticker)) decode failed: \(error). Body written to /tmp/predictbar-last-market-\(ticker).json")
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
        
        PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
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
                // if let jsonStr = String(data: data, encoding: .utf8) {
                //      print("Event Response for \(eventTicker): \(jsonStr)")
                // }
                
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
    }
    
    func fetchSeries(seriesTicker: String, completion: @escaping (Result<Series, Error>) -> Void) {
        guard let request = authenticatedRequest(to: "/series/\(seriesTicker)") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
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
        // endpoint might contain query params, e.g. /portfolio/fills?limit=100
        // URL needs full endpoint. Signature needs path ONLY.
        
        guard let url = URL(string: baseURL.absoluteString + endpoint) else { return nil }
        
        // Retrieve credentials securely
        guard let credentials = try? CredentialsManager.shared.getCredentials() else {
            print("❌ Missing API credentials. Please add them in Settings.")
            return nil
        }
        
        // print("DEBUG: Requesting URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        
        // Extract path component for signing (strip query params)
        // If endpoint is "/portfolio/fills?limit=100", path should be "/trade-api/v2/portfolio/fills"
        let pathOnly: String
        if let components = URLComponents(string: endpoint) {
            pathOnly = "/trade-api/v2" + components.path
        } else {
             // Fallback if parsing fails (unlikely)
             pathOnly = "/trade-api/v2" + endpoint.split(separator: "?")[0]
        }
        
        let messageToSign = timestamp + method + pathOnly
        
        guard let signature = CryptoUtils.sign(message: messageToSign, key: credentials.signingKey) else {
            return nil
        }
        
        request.addValue(credentials.apiKey, forHTTPHeaderField: "KALSHI-ACCESS-KEY")
        request.addValue(timestamp, forHTTPHeaderField: "KALSHI-ACCESS-TIMESTAMP")
        request.addValue(signature, forHTTPHeaderField: "KALSHI-ACCESS-SIGNATURE")
        
        return request
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
        let close: Int?
        let closeDollars: String?
        let high: Int?
        let low: Int?
    }
    
    /// Fetch candlestick data for a market
    func fetchCandles(seriesTicker: String, marketTicker: String, startTs: Int, endTs: Int, completion: @escaping (Result<[Candlestick], Error>) -> Void) {
        var components = URLComponents(string: "/series/\(seriesTicker)/markets/\(marketTicker)/candlesticks")
        components?.queryItems = [
            URLQueryItem(name: "start_ts", value: String(startTs)),
            URLQueryItem(name: "end_ts", value: String(endTs)),
            URLQueryItem(name: "period_interval", value: "1") // 1 minute candles
        ]
        
        guard let endpoint = components?.string,
              let request = authenticatedRequest(to: endpoint) else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(URLError(.badServerResponse))); return }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(CandlestickResponse.self, from: data)
                completion(.success(response.candlesticks))
            } catch {
                completion(.failure(error))
            }
        }.resume()
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
            // Logging disabled for production
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
            PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
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
                        onResult(.failure(URLError(.cannotParseResponse)))
                    } else {
                        onResult(.success(prices))
                    }
                } catch {
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
        
        guard seriesTicker != nil else {
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
        
    }
    
    // MARK: - Portfolio Endpoints
    
    struct FillsResponse: Decodable {
        let fills: [Fill]?
        let cursor: String?
    }
    
    func fetchFills(cursor: String? = nil, limit: Int = 100, completion: @escaping (Result<FillsResponse, Error>) -> Void) {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        var components = URLComponents(string: "/portfolio/fills")
        components?.queryItems = queryItems

        guard let endpoint = components?.string,
              let request = authenticatedRequest(to: endpoint) else {
            completion(.failure(URLError(.badURL)))
            return
        }

        PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(URLError(.badServerResponse))); return }

            do {
                let response = try JSONDecoder().decode(FillsResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func fetchAllFills(completion: @escaping (Result<[Fill], Error>) -> Void) {
        var allFills: [Fill] = []

        func fetchPage(cursor: String?) {
            fetchFills(cursor: cursor, limit: 100) { result in
                switch result {
                case .success(let response):
                    let pageFills = response.fills ?? []
                    allFills.append(contentsOf: pageFills)

                    if let nextCursor = response.cursor, !nextCursor.isEmpty, !pageFills.isEmpty {
                        fetchPage(cursor: nextCursor)
                    } else {
                        completion(.success(allFills))
                    }
                case .failure(let error):
                    if allFills.isEmpty {
                        completion(.failure(error))
                    } else {
                        // Return what we have so far
                        completion(.success(allFills))
                    }
                }
            }
        }

        fetchPage(cursor: nil)
    }

    struct PublicTrade: Decodable {
        let price: Int
        let count: Int
        let createdTime: String
        let takerSide: String
    }

    struct TradesResponse: Decodable {
        let trades: [PublicTrade]
        let cursor: String?
    }
    
    func fetchTrades(ticker: String, minTs: Int? = nil, maxTs: Int? = nil, limit: Int = 1000, cursor: String? = nil, completion: @escaping (Result<TradesResponse, Error>) -> Void) {
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let minTs = minTs { queryItems.append(URLQueryItem(name: "min_ts", value: String(minTs))) }
        if let maxTs = maxTs { queryItems.append(URLQueryItem(name: "max_ts", value: String(maxTs))) }
        if let cursor = cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        
        // Note: Kalshi API /markets/{ticker}/trades endpoint
        var components = URLComponents(string: "/markets/\(ticker)/trades")
        components?.queryItems = queryItems
        
        guard let endpoint = components?.string,
              let request = authenticatedRequest(to: endpoint) else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        PinnedURLSession.shared.session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(URLError(.badServerResponse))); return }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(TradesResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
