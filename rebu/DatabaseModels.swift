import Foundation

// MARK: - Restaurant (read from "restaurants" table)

struct RestaurantRow: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let address: String?
    let phone: String?
    let latitude: Double?
    let longitude: Double?
    let ownerId: UUID?
    let isOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, address, phone, latitude, longitude
        case ownerId = "owner_id"
        case isOnline = "is_online"
    }
}

// MARK: - Menu Item (read from "menu_items" table)

struct MenuItemRow: Codable, Identifiable, Sendable {
    let id: Int
    let restaurantId: Int
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
    let customerId: UUID?
    let restaurantId: Int
    let menuId: Int
    let quantity: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case restaurantId = "restaurant_id"
        case menuId = "menu_id"
        case quantity, status
    }
}

// MARK: - Order (read from "orders" table)

struct OrderRow: Codable, Identifiable, Sendable {
    let id: Int
    let customerId: UUID?
    let restaurantId: Int?
    let driverId: UUID?
    let menuId: Int?
    let quantity: Int?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case restaurantId = "restaurant_id"
        case driverId = "driver_id"
        case menuId = "menu_id"
        case quantity, status
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
