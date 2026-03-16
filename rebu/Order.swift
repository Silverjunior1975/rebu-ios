import Foundation



enum OrderStatus: String {

    case new = "NEW"

    case accepted = "ACCEPTED"

    case ready = "READY"

    case acceptedByDriver = "ACCEPTED_BY_DRIVER"

    case pickedUp = "PICKED_UP"

    case delivered = "DELIVERED"

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
