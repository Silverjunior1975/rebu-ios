import Foundation



enum OrderStatus: String {

    case new = "new"

    case accepted = "accepted"

    case ready = "ready"

    case pending = "pending"

    case pickedUp = "picked_up"

    case delivered = "delivered"

}

struct OrderItem:Identifiable {
    let id = UUID()
    let name: String
    let quantity: Int
    let price: Double
}
struct Order: Identifiable {
   
    let id: Int
    let items: [OrderItem]
    let total: Double
    
    let restaurantName: String

    let restaurantAddress: String

    let customerAddress: String
    let customerPhone: String
    var status: OrderStatus
    var driverId: UUID?
}
