import Foundation



struct Restaurant: Identifiable {

    let id: UUID

    let name: String

    let products: [Product]

}



struct Product: Identifiable {

    let id: UUID

    let name: String

    let price: Double
    struct OrderItem: Identifiable {
        let id = UUID()
        let name: String
        let quantity: Int
        let price: Double
    }
}


