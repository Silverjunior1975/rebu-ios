import Foundation
import Combine
import UIKit

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
                .select("*, order_items(*)")
                .execute()
                .value

            let fetchedOrders = rows.map { row in
                Order(
                    id: row.id,
                    items: (row.orderItems ?? []).map { item in
                        OrderItem(
                            name: item.name,
                            quantity: item.quantity,
                            price: item.price
                        )
                    },
                    total: row.total,
                    restaurantName: row.restaurantName,
                    restaurantAddress: row.restaurantAddress,
                    customerAddress: row.customerAddress,
                    customerPhone: row.customerPhone,
                    status: OrderStatus(rawValue: row.status) ?? .new,
                    driverId: row.driverId
                )
            }

            self.orders = fetchedOrders
        } catch {
            print("Error fetching orders: \(error)")
        }
    }

    // MARK: - Place Order (insert into orders + order_items)

    func placeOrder(
        restaurantId: UUID,
        restaurantName: String,
        restaurantAddress: String,
        customerName: String,
        customerAddress: String,
        customerPhone: String,
        items: [Product],
        deliveryFee: Double
    ) async -> Bool {
        let itemsTotal = items.reduce(0.0) { $0 + $1.price }
        let total = itemsTotal + deliveryFee

        let orderInsert = OrderInsert(
            restaurantId: restaurantId,
            restaurantName: restaurantName,
            restaurantAddress: restaurantAddress,
            customerName: customerName,
            customerAddress: customerAddress,
            customerPhone: customerPhone,
            total: total,
            deliveryFee: deliveryFee,
            status: OrderStatus.new.rawValue
        )

        do {
            let createdOrder: OrderRow = try await supabaseClient
                .from("orders")
                .insert(orderInsert)
                .select()
                .single()
                .execute()
                .value

            let orderItems = items.map { product in
                OrderItemInsert(
                    orderId: createdOrder.id,
                    name: product.name,
                    quantity: 1,
                    price: product.price
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

    func updateStatus(for orderID: UUID, to newStatus: OrderStatus) async {
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

    func acceptOrder(orderID: UUID, driverID: UUID) async {
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

    func pickUpOrder(orderID: UUID) async {
        await updateStatus(for: orderID, to: .pickedUp)
    }

    // MARK: - Deliver Order

    func deliverOrder(orderID: UUID) async {
        await updateStatus(for: orderID, to: .delivered)
    }

    // MARK: - Mark Delivered

    func markDelivered(orderID: UUID) async {
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


