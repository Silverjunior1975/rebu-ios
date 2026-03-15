import Foundation

// MARK: - Restaurant (read from "restaurants" table)

struct RestaurantRow: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let isOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, address, latitude, longitude
        case isOnline = "is_online"
    }
}

// MARK: - Menu Item (read from "menu_items" table)

struct MenuItemRow: Codable, Identifiable, Sendable {
    let id: UUID
    let restaurantId: UUID
    let name: String
    let price: Double
    let description: String?
    let category: String?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case restaurantId = "restaurant_id"
        case name, price, description, category
        case imageUrl = "image_url"
    }
}

// MARK: - Order (insert into "orders" table)

struct OrderInsert: Codable, Sendable {
    let restaurantId: UUID
    let restaurantName: String
    let restaurantAddress: String
    let customerName: String
    let customerAddress: String
    let customerPhone: String
    let total: Double
    let deliveryFee: Double
    let status: String

    enum CodingKeys: String, CodingKey {
        case restaurantId = "restaurant_id"
        case restaurantName = "restaurant_name"
        case restaurantAddress = "restaurant_address"
        case customerName = "customer_name"
        case customerAddress = "customer_address"
        case customerPhone = "customer_phone"
        case total
        case deliveryFee = "delivery_fee"
        case status
    }
}

// MARK: - Order (read from "orders" table, with nested order_items)

struct OrderRow: Codable, Identifiable, Sendable {
    let id: UUID
    let restaurantId: UUID?
    let restaurantName: String
    let restaurantAddress: String
    let customerName: String?
    let customerAddress: String
    let customerPhone: String
    let total: Double
    let deliveryFee: Double?
    let status: String
    let driverId: UUID?
    let orderItems: [OrderItemRow]?

    enum CodingKeys: String, CodingKey {
        case id
        case restaurantId = "restaurant_id"
        case restaurantName = "restaurant_name"
        case restaurantAddress = "restaurant_address"
        case customerName = "customer_name"
        case customerAddress = "customer_address"
        case customerPhone = "customer_phone"
        case total
        case deliveryFee = "delivery_fee"
        case status
        case driverId = "driver_id"
        case orderItems = "order_items"
    }
}

// MARK: - Order Item (insert into "order_items" table)

struct OrderItemInsert: Codable, Sendable {
    let orderId: UUID
    let name: String
    let quantity: Int
    let price: Double

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case name, quantity, price
    }
}

// MARK: - Order Item (read from "order_items" table)

struct OrderItemRow: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let quantity: Int
    let price: Double

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, price
    }
}

// MARK: - Status Update (for PATCH to "orders" table)

struct StatusUpdate: Codable, Sendable {
    let status: String
}

// MARK: - Driver Accept Update (for PATCH to "orders" table)

struct DriverAcceptUpdate: Codable, Sendable {
    let driverId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case driverId = "driver_id"
        case status
    }
}

// MARK: - Driver (read from "drivers" table)

struct DriverRow: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String?
    let phone: String?
    let isApproved: Bool?
    let isBlocked: Bool?
    let isOnline: Bool?
    let stripeAccountId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, phone
        case isApproved = "is_approved"
        case isBlocked = "is_blocked"
        case isOnline = "is_online"
        case stripeAccountId = "stripe_account_id"
    }
}

// MARK: - Driver Upsert (for setting online/offline status)

struct DriverUpsert: Codable, Sendable {
    let id: UUID
    let isOnline: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case isOnline = "is_online"
    }
}
