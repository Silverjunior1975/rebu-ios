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

// Local insert struct with delivery_fee, total, and customer_id for RLS
private struct FullOrderInsert: Codable, Sendable {
    let customerId: String?
    let restaurantId: Int
    let status: String
    let itemsTotal: Double
    let deliveryFee: Double
    let totalPrice: Double
    let customerName: String?
    let deliveryAddress: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
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
                        let mId = item.menuId ?? 0
                        let info = menuItemPrices[mId]
                        return OrderItem(
                            name: info?.name ?? "Item #\(mId)",
                            quantity: item.quantity,
                            price: item.priceEach ?? info?.price ?? 0
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
                    customerAddress: row.deliveryAddress ?? "",
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

        // Get authenticated user ID for customer_id (non-fatal if unavailable)
        var userId: String?
        do {
            let session = try await supabaseClient.auth.session
            userId = session.user.id.uuidString
            print("REBU AUTH: user id = \(userId ?? "nil")")
        } catch {
            print("REBU AUTH: No active session (\(error.localizedDescription))")
            // Try anonymous sign-in as fallback
            do {
                let session = try await supabaseClient.auth.signInAnonymously()
                userId = session.user.id.uuidString
                print("REBU AUTH: anonymous user id = \(userId ?? "nil")")
            } catch {
                print("REBU AUTH: Anonymous sign-in failed (\(error.localizedDescription))")
                print("REBU AUTH: Proceeding without customer_id")
            }
        }

        // Calculate totals
        let itemsTotal = items.reduce(0.0) { $0 + $1.price * Double($1.quantity) }
        let deliveryFee = DeliveryPricing.deliveryFee(distanceMiles: distanceMiles)
        let total = itemsTotal + deliveryFee
        print("REBU: restaurant=\(restaurantId), items_total=\(itemsTotal), delivery_fee=\(deliveryFee), total=\(total), items=\(items.count)")

        // Build the insert payload
        let orderInsert = FullOrderInsert(
            customerId: userId,
            restaurantId: restaurantId,
            status: OrderStatus.new.rawValue,
            itemsTotal: itemsTotal,
            deliveryFee: deliveryFee,
            totalPrice: total,
            customerName: customerName,
            deliveryAddress: address,
            phone: phone
        )

        // Step 1: Insert into orders table (plain execute — no response decoding)
        do {
            print("REBU: Inserting into orders table...")
            try await supabaseClient
                .from("orders")
                .insert(orderInsert)
                .execute()
            print("REBU: Order insert succeeded")
        } catch {
            print("REBU ERROR inserting order: \(error)")
            print("REBU ERROR full: \(String(describing: error))")
            print("=== REBU PLACE ORDER FAILED ===")
            return false
        }

        // Step 2: Get the order ID we just created (query by unique fields)
        var orderId: Int?
        do {
            let recentOrders: [InsertedOrderID] = try await supabaseClient
                .from("orders")
                .select("id")
                .eq("restaurant_id", value: restaurantId)
                .eq("phone", value: phone)
                .order("id", ascending: false)
                .limit(1)
                .execute()
                .value
            orderId = recentOrders.first?.id
            print("REBU ORDER ID: \(orderId ?? -1)")
        } catch {
            print("REBU: Could not fetch order ID: \(error.localizedDescription)")
        }

        // Step 3: Insert order items (only if we got the order ID)
        if let orderId = orderId {
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
                print("REBU: Inserting \(orderItems.count) items for order \(orderId)...")
                try await supabaseClient
                    .from("order_items")
                    .insert(orderItems)
                    .execute()
                print("REBU ORDER ITEMS INSERTED: \(orderItems.count) items")
            } catch {
                print("REBU ERROR inserting order_items: \(error.localizedDescription)")
            }
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
                    status: OrderStatus.pending.rawValue
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


