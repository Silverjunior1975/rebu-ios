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

            // Group order rows by restaurant_id + customer_id + status to form logical orders
            // Each row is one menu item; group them into Order objects
            var grouped: [String: [OrderRow]] = [:]
            for row in rows {
                let key = "\(row.restaurantId ?? 0)-\(row.customerId?.uuidString ?? "nil")-\(row.status)"
                grouped[key, default: []].append(row)
            }

            let fetchedOrders = grouped.values.compactMap { group -> Order? in
                guard let first = group.first else { return nil }
                return Order(
                    id: first.id,
                    items: group.map { row in
                        OrderItem(name: "Item #\(row.menuId ?? 0)", quantity: row.quantity ?? 1, price: 0)
                    },
                    total: 0,
                    restaurantName: "Restaurant #\(first.restaurantId ?? 0)",
                    restaurantAddress: "",
                    customerAddress: "",
                    customerPhone: "",
                    status: OrderStatus(rawValue: first.status) ?? .new,
                    driverId: first.driverId
                )
            }

            self.orders = fetchedOrders
        } catch {
            print("Error fetching orders: \(error)")
        }
    }

    // MARK: - Place Order (insert into orders table)

    func placeOrder(
        customerId: UUID?,
        restaurantId: Int,
        items: [(menuId: Int, quantity: Int)]
    ) async -> Bool {
        let orderInserts = items.map { item in
            OrderInsert(
                customerId: customerId,
                restaurantId: restaurantId,
                menuId: item.menuId,
                quantity: item.quantity,
                status: OrderStatus.new.rawValue
            )
        }

        do {
            try await supabaseClient
                .from("orders")
                .insert(orderInserts)
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

    func acceptOrder(orderID: Int, driverID: UUID) async {
        do {
            try await supabaseClient
                .from("orders")
                .update(DriverAcceptUpdate(
                    driverId: driverID,
                    status: OrderStatus.acceptedByDriver.rawValue
                ))
                .eq("id", value: orderID)
                .execute()

            await fetchOrders()
        } catch {
            print("Error accepting order: \(error)")
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


