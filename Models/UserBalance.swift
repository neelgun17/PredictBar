import Foundation

struct UserBalance: Codable {
    let balance: Int // In cents
    let available: Int // In cents
    

}

struct BalanceResponse: Codable {
    let balance: UserBalance
}
