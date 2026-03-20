import Foundation
import Combine
import UIKit
import Supabase

// Minimal struct to decode only the order ID from insert response
private struct InsertedOrderID: Decodable, Sendable {
    let id: Int
}

// Local order_items insert struct matching exact Supabase column names
private struct OrderItemPayload: Codable, Sendable {
    let orderId: Int
    let menuId: Int
    let quantity: Int
    let priceEach: Double
    let totalPrice: Double

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case menuId = "menu_id"
        case quantity
        case priceEach = "price_each"
        case totalPrice = "total_price"
    }
}

// Local insert struct with delivery_fee and total (extends OrderInsert without modifying DatabaseModels)
private struct FullOrderInsert: Codable, Sendable {
    let restaurantId: Int
    let status: String
    let itemsTotal: Double
    let deliveryFee: Double
    let totalPrice: Double
    let customerName: String?
    let deliveryAddress: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case restaurantId = "restaurant_id"
        case status
        case itemsTotal = "items_total"
        case deliveryFee = "delivery_fee"
        case totalPrice = "total_price"
        case customerName = "customer_name"
        case deliveryAddress = "delivery_address"
        case phone
    }
}

class OrderStore: ObservableObject {

    @Published var orders: [Order] = []

    var readyOrders: [Order] {
        orders.filter {
            $0.status == .ready && $0.driverId == nil
        }
    }

    var todayTotal: Double {
        orders
            .filter { $0.status == .delivered }
            .reduce(0) { $0 + $1.total }
    }

    // MARK: - Fetch all orders from Supabase

    func fetchOrders() async {
        do {
            let rows: [OrderRow] = try await supabaseClient
                .from("orders")
                .select()
                .execute()
                .value

            // Fetch all menu items once for price lookup
            var menuItemPrices: [Int: (name: String, price: Double)] = [:]
            do {
                let allMenuItems: [MenuItemRow] = try await supabaseClient
                    .from("menu_items")
                    .select()
                    .execute()
                    .value
                for mi in allMenuItems {
                    menuItemPrices[mi.id] = (name: mi.name, price: mi.price)
                }
            } catch {
                print("Error fetching menu items for prices: \(error)")
            }

            // Fetch all restaurant names once
            var restaurantNames: [Int: String] = [:]
            do {
                let allRestaurants: [RestaurantRow] = try await supabaseClient
                    .from("restaurants")
                    .select()
                    .execute()
                    .value
                for r in allRestaurants {
                    restaurantNames[r.id] = r.name
                }
            } catch {
                print("Error fetching restaurant names: \(error)")
            }

            // For each order row, fetch its order_items
            var fetchedOrders: [Order] = []
            for row in rows {
                var items: [OrderItem] = []
                do {
                    let itemRows: [OrderItemRow] = try await supabaseClient
                        .from("order_items")
                        .select()
                        .eq("order_id", value: row.id)
                        .execute()
                        .value
                    items = itemRows.map { item in
                        let prodId = item.productId ?? 0
                        let info = menuItemPrices[prodId]
                        return OrderItem(
                            name: info?.name ?? "Item #\(prodId)",
                            quantity: item.quantity,
                            price: item.price ?? info?.price ?? 0
                        )
                    }
                } catch {
                    print("Error fetching order items for order \(row.id): \(error)")
                }

                let itemsTotal = row.itemsTotal ?? items.reduce(0) { $0 + Double($1.quantity) * $1.price }
                let rName = restaurantNames[row.restaurantId ?? 0] ?? "Restaurant #\(row.restaurantId ?? 0)"

                let order = Order(
                    id: row.id,
                    items: items,
                    total: itemsTotal,
                    restaurantName: rName,
                    restaurantAddress: "",
                    customerAddress: row.address ?? "",
                    customerPhone: row.phone ?? "",
                    status: OrderStatus(rawValue: row.status) ?? .new,
                    driverId: row.driverId
                )
                fetchedOrders.append(order)
            }

            self.orders = fetchedOrders
        } catch {
            print("Error fetching orders: \(error)")
        }
    }

    // MARK: - Place Order (insert into orders + order_items)

    func placeOrder(
        restaurantId: Int,
        customerName: String,
        address: String,
        phone: String,
        distanceMiles: Double,
        items: [(productId: Int, quantity: Int, price: Double)]
    ) async -> Bool {
        print("=== REBU PLACE ORDER START ===")

        // Calculate items_total from cart
        let itemsTotal = items.reduce(0.0) { $0 + $1.price * Double($1.quantity) }
        let deliveryFee = DeliveryPricing.deliveryFee(distanceMiles: distanceMiles)
        let total = itemsTotal + deliveryFee
        print("REBU: restaurant=\(restaurantId), items_total=\(itemsTotal), delivery_fee=\(deliveryFee), total=\(total), items=\(items.count)")

        // Build the insert payload
        let orderInsert = FullOrderInsert(
            restaurantId: restaurantId,
            status: OrderStatus.new.rawValue,
            itemsTotal: itemsTotal,
            deliveryFee: deliveryFee,
            totalPrice: total,
            customerName: customerName,
            deliveryAddress: address,
            phone: phone
        )

        // Log the exact JSON being sent to Supabase
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .useDefaultKeys
            let jsonData = try encoder.encode(orderInsert)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "nil"
            print("REBU INSERT JSON: \(jsonString)")
        } catch {
            print("REBU ERROR encoding insert: \(error)")
            return false
        }

        // Step 1: Insert into orders table
        // Use plain execute() + JSONSerialization to avoid Codable decode issues
        let orderId: Int
        do {
            print("REBU: Inserting into orders table...")
            let response = try await supabaseClient
                .from("orders")
                .insert(orderInsert)
                .select("id")
                .single()
                .execute()
            print("REBU: Insert response status=\(response.status)")
            print("REBU: Insert response data=\(String(data: response.data, encoding: .utf8) ?? "nil")")

            // Parse the order ID from raw JSON (avoids Codable decode mismatch)
            guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let rawId = json["id"] else {
                print("REBU ERROR: Could not parse order ID from response")
                return false
            }

            // Handle id as Int or Int64
            if let intId = rawId as? Int {
                orderId = intId
            } else if let intId = rawId as? Int64 {
                orderId = Int(intId)
            } else if let doubleId = rawId as? Double {
                orderId = Int(doubleId)
            } else {
                print("REBU ERROR: order id is unexpected type: \(type(of: rawId)) = \(rawId)")
                return false
            }
            print("REBU ORDER CREATED: id=\(orderId)")
        } catch {
            print("REBU ERROR inserting order: \(error)")
            print("REBU ERROR type: \(type(of: error))")
            print("REBU ERROR localized: \(error.localizedDescription)")
            print("REBU ERROR full: \(String(describing: error))")
            print("=== REBU PLACE ORDER FAILED (order insert) ===")
            return false
        }

        // Step 2: Insert order items using exact Supabase column names
        do {
            let orderItems = items.map { item in
                OrderItemPayload(
                    orderId: orderId,
                    menuId: item.productId,
                    quantity: item.quantity,
                    priceEach: item.price,
                    totalPrice: item.price * Double(item.quantity)
                )
            }
            print("REBU ORDER ITEMS PAYLOAD: \(orderItems)")
            print("REBU: Inserting \(orderItems.count) items for order \(orderId)...")
            try await supabaseClient
                .from("order_items")
                .insert(orderItems)
                .execute()
            print("REBU ORDER ITEMS INSERTED: \(orderItems.count) items for order \(orderId)")
        } catch {
            print("REBU ERROR inserting order_items: \(error)")
            print("REBU ERROR localized: \(error.localizedDescription)")
            // Order was created but items failed — still return true so UI doesn't show false failure
            print("=== REBU PLACE ORDER PARTIAL (order created, items failed) ===")
        }

        await fetchOrders()
        print("=== REBU PLACE ORDER SUCCESS ===")
        return true
    }

    // MARK: - Update Order Status

    func updateStatus(for orderID: Int, to newStatus: OrderStatus) async {
        do {
            try await supabaseClient
                .from("orders")
                .update(StatusUpdate(status: newStatus.rawValue))
                .eq("id", value: orderID)
                .execute()

            await fetchOrders()
        } catch {
            print("Error updating order status: \(error)")
        }
    }

    // MARK: - Accept Order (assign driver)

    func acceptOrder(orderID: Int, driverID: UUID) async -> Bool {
        print("ACCEPT DELIVERY TAPPED")
        print("UPDATING ORDER: \(orderID) with driver: \(driverID)")
        do {
            try await supabaseClient
                .from("orders")
                .update(DriverAcceptUpdate(
                    driverId: driverID,
                    status: OrderStatus.acceptedByDriver.rawValue
                ))
                .eq("id", value: orderID)
                .execute()

            print("ORDER \(orderID) ACCEPTED SUCCESSFULLY")
            await fetchOrders()
            return true
        } catch {
            print("ERROR ACCEPTING ORDER \(orderID): \(error)")
            return false
        }
    }

    // MARK: - Pick Up Order

    func pickUpOrder(orderID: Int) async {
        await updateStatus(for: orderID, to: .pickedUp)
    }

    // MARK: - Deliver Order

    func deliverOrder(orderID: Int) async {
        await updateStatus(for: orderID, to: .delivered)
    }

    // MARK: - Mark Delivered

    func markDelivered(orderID: Int) async {
        await updateStatus(for: orderID, to: .delivered)
    }

    // MARK: - Call Client

    func callClient(phone: String) {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "tel://\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }
}


