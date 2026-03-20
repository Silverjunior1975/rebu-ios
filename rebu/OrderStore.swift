import Foundation
import Combine
import UIKit
import Supabase

// Minimal struct to decode only the order ID from insert response
private struct InsertedOrderID: Decodable, Sendable {
    let id: Int
}

// Local insert struct with delivery_fee and total (extends OrderInsert without modifying DatabaseModels)
private struct FullOrderInsert: Codable, Sendable {
    let restaurantId: Int
    let status: String
    let itemsTotal: Double
    let deliveryFee: Double
    let totalPrice: Double
    let customerName: String?
    let address: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case restaurantId = "restaurant_id"
        case status
        case itemsTotal = "items_total"
        case deliveryFee = "delivery_fee"
        case totalPrice = "total_price"
        case customerName = "customer_name"
        case address
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
        do {
            // Calculate items_total from cart
            let itemsTotal = items.reduce(0.0) { $0 + $1.price * Double($1.quantity) }
            let deliveryFee = DeliveryPricing.deliveryFee(distanceMiles: distanceMiles)
            let total = itemsTotal + deliveryFee
            print("PLACING ORDER: restaurant=\(restaurantId), items_total=\(itemsTotal), delivery_fee=\(deliveryFee), total=\(total), items=\(items.count)")

            // Step 1: Insert order row and get back the created order
            let orderInsert = FullOrderInsert(
                restaurantId: restaurantId,
                status: OrderStatus.new.rawValue,
                itemsTotal: itemsTotal,
                deliveryFee: deliveryFee,
                totalPrice: total,
                customerName: customerName,
                address: address,
                phone: phone
            )

            // Insert order and decode only the id (avoids OrderRow decode mismatch)
            let insertedOrder: InsertedOrderID = try await supabaseClient
                .from("orders")
                .insert(orderInsert)
                .select("id")
                .single()
                .execute()
                .value

            let orderId = insertedOrder.id
            print("ORDER CREATED: id=\(orderId)")

            // Step 2: Insert order items with the created order's id
            let orderItems = items.map { item in
                OrderItemInsert(
                    orderId: orderId,
                    productId: item.productId,
                    quantity: item.quantity,
                    price: item.price
                )
            }

            try await supabaseClient
                .from("order_items")
                .insert(orderItems)
                .execute()

            print("ORDER ITEMS INSERTED: \(orderItems.count) items for order \(orderId)")

            await fetchOrders()
            return true
        } catch {
            print("ERROR PLACING ORDER: \(error)")
            print("ERROR DETAILS: \(error.localizedDescription)")
            return false
        }
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


