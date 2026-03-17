import Foundation
import Combine
import UIKit
import Supabase

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
                        let menuId = item.menuItemId ?? 0
                        let info = menuItemPrices[menuId]
                        return OrderItem(
                            name: info?.name ?? "Item #\(menuId)",
                            quantity: item.quantity,
                            price: info?.price ?? 0
                        )
                    }
                } catch {
                    print("Error fetching order items for order \(row.id): \(error)")
                }

                let itemsTotal = items.reduce(0) { $0 + Double($1.quantity) * $1.price }
                let rName = restaurantNames[row.restaurantId ?? 0] ?? "Restaurant #\(row.restaurantId ?? 0)"

                let order = Order(
                    id: row.id,
                    items: items,
                    total: itemsTotal,
                    restaurantName: rName,
                    restaurantAddress: "",
                    customerAddress: row.deliveryAddress ?? "",
                    customerPhone: "",
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
        customerId: UUID?,
        restaurantId: Int,
        deliveryAddress: String?,
        items: [(menuItemId: Int, quantity: Int)]
    ) async -> Bool {
        do {
            // Step 1: Insert order row and get back the created order
            let orderInsert = OrderInsert(
                customerId: customerId,
                restaurantId: restaurantId,
                status: OrderStatus.new.rawValue,
                deliveryAddress: deliveryAddress
            )

            let createdOrder: OrderRow = try await supabaseClient
                .from("orders")
                .insert(orderInsert)
                .select()
                .single()
                .execute()
                .value

            // Step 2: Insert order items with the created order's id
            let orderItems = items.map { item in
                OrderItemInsert(
                    orderId: createdOrder.id,
                    menuItemId: item.menuItemId,
                    quantity: item.quantity
                )
            }

            try await supabaseClient
                .from("order_items")
                .insert(orderItems)
                .execute()

            await fetchOrders()
            return true
        } catch {
            print("Error placing order: \(error)")
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


