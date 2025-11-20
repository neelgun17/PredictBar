import Foundation

struct UserBalance: Codable {
    let balance: Int // In cents
    let available: Int // In cents
    
    var balanceInDollars: Double {
        return Double(balance) / 100.0
    }
}

struct BalanceResponse: Codable {
    let balance: UserBalance
}
