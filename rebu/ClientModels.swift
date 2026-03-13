import Foundation

struct Restaurant: Identifiable {
    let id: UUID
    let name: String
    let address: String
    let products: [Product]
}

struct Product: Identifiable {
    let id: UUID
    let name: String
    let price: Double
}
