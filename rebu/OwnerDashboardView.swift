import SwiftUI

/// Owner dashboard — macOS only (Mac Catalyst).
/// Shows REBU earnings, driver/restaurant activity, and admin controls.
/// This view must NOT appear in the iPhone App Store build.
struct OwnerDashboardView: View {

    @State private var deliveredOrders: [OrderRow] = []
    @State private var allDrivers: [DriverRow] = []
    @State private var allRestaurants: [RestaurantRow] = []
    @State private var isLoading: Bool = true

    // MARK: - Computed Totals

    private var totalOrderValue: Double {
        deliveredOrders.reduce(0) { $0 + $1.total }
    }

    private var totalDeliveryFees: Double {
        deliveredOrders.reduce(0) { $0 + ($1.deliveryFee ?? 0) }
    }

    private var totalRestaurantPayouts: Double {
        deliveredOrders.reduce(0) { total, order in
            let itemsTotal = (order.orderItems ?? []).reduce(0.0) { $0 + Double($1.quantity) * $1.price }
            return total + itemsTotal
        }
    }

    private var totalDriverPayouts: Double {
        deliveredOrders.reduce(0) { total, order in
            let deliveryFee = order.deliveryFee ?? 0
            let driverPayout = max(2.50, deliveryFee - 2.50)
            return total + driverPayout
        }
    }

    private var totalRebuEarnings: Double {
        totalDeliveryFees - totalDriverPayouts
    }

    /// Number of deliveries grouped by driver
    private var driverDeliveryCounts: [(driverId: UUID, count: Int)] {
        var counts: [UUID: Int] = [:]
        for order in deliveredOrders {
            guard let dId = order.driverId else { continue }
            counts[dId, default: 0] += 1
        }
        return counts.map { (driverId: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Number of orders per restaurant (all statuses)
    private var restaurantOrderCounts: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for order in deliveredOrders {
            counts[order.restaurantName, default: 0] += 1
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading dashboard...")
                        Spacer()
                    }
                } else {

                    // MARK: - Earnings Summary
                    Section("REBU Earnings") {
                        statRow("Total REBU Earnings", totalRebuEarnings)
                        statRow("Total Driver Payouts", totalDriverPayouts)
                        statRow("Total Restaurant Payouts", totalRestaurantPayouts)
                        statRow("Total Order Value", totalOrderValue)
                        statRow("Total Delivery Fees", totalDeliveryFees)
                        Text("Delivered Orders: \(deliveredOrders.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // MARK: - Driver Activity
                    Section("Driver Activity") {
                        if driverDeliveryCounts.isEmpty {
                            Text("No driver activity yet")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(driverDeliveryCounts, id: \.driverId) { entry in
                                HStack {
                                    Text("Driver \(entry.driverId.uuidString.prefix(8))")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(entry.count) deliveries")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // MARK: - Active Restaurants
                    Section("Restaurants") {
                        if allRestaurants.isEmpty {
                            Text("No restaurants")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(allRestaurants) { restaurant in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(restaurant.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(restaurant.address ?? "No address")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    let count = restaurantOrderCounts.first { $0.name == restaurant.name }?.count ?? 0
                                    Text("\(count) orders")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Button {
                                        Task { await blockRestaurant(restaurant.id) }
                                    } label: {
                                        Text("Block")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    // MARK: - Drivers Management
                    Section("Drivers") {
                        if allDrivers.isEmpty {
                            Text("No registered drivers")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(allDrivers) { driver in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(driver.name ?? "Driver \(driver.id.uuidString.prefix(8))")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        HStack(spacing: 8) {
                                            if driver.isApproved == true {
                                                Text("Approved")
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                            }
                                            if driver.isBlocked == true {
                                                Text("Blocked")
                                                    .font(.caption2)
                                                    .foregroundColor(.red)
                                            }
                                        }
                                    }
                                    Spacer()

                                    if driver.isApproved != true {
                                        Button {
                                            Task { await approveDriver(driver.id) }
                                        } label: {
                                            Text("Approve")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }

                                    Button {
                                        Task { await blockDriver(driver.id, block: driver.isBlocked != true) }
                                    } label: {
                                        Text(driver.isBlocked == true ? "Unblock" : "Block")
                                            .font(.caption)
                                            .foregroundColor(driver.isBlocked == true ? .blue : .red)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("REBU Owner")
            .task {
                await loadDashboard()
            }
            .refreshable {
                await loadDashboard()
            }
        }
    }

    // MARK: - Helpers

    private func statRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(String(format: "$%.2f", value))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Data Loading

    private func loadDashboard() async {
        isLoading = true

        async let ordersTask: () = fetchDeliveredOrders()
        async let driversTask: () = fetchDrivers()
        async let restaurantsTask: () = fetchRestaurants()

        await ordersTask
        await driversTask
        await restaurantsTask

        isLoading = false
    }

    private func fetchDeliveredOrders() async {
        do {
            deliveredOrders = try await supabaseClient
                .from("orders")
                .select("*, order_items(*)")
                .eq("status", value: "DELIVERED")
                .execute()
                .value
        } catch {
            print("Owner: Error fetching delivered orders: \(error)")
        }
    }

    private func fetchDrivers() async {
        do {
            allDrivers = try await supabaseClient
                .from("drivers")
                .select()
                .execute()
                .value
        } catch {
            print("Owner: Error fetching drivers: \(error)")
            // drivers table may not exist yet — fail silently
        }
    }

    private func fetchRestaurants() async {
        do {
            allRestaurants = try await supabaseClient
                .from("restaurants")
                .select()
                .execute()
                .value
        } catch {
            print("Owner: Error fetching restaurants: \(error)")
        }
    }

    // MARK: - Admin Actions

    private func approveDriver(_ driverId: UUID) async {
        do {
            struct ApproveUpdate: Codable {
                let isApproved: Bool
                enum CodingKeys: String, CodingKey {
                    case isApproved = "is_approved"
                }
            }
            try await supabaseClient
                .from("drivers")
                .update(ApproveUpdate(isApproved: true))
                .eq("id", value: driverId)
                .execute()
            await fetchDrivers()
        } catch {
            print("Owner: Error approving driver: \(error)")
        }
    }

    private func blockDriver(_ driverId: UUID, block: Bool) async {
        do {
            struct BlockUpdate: Codable {
                let isBlocked: Bool
                enum CodingKeys: String, CodingKey {
                    case isBlocked = "is_blocked"
                }
            }
            try await supabaseClient
                .from("drivers")
                .update(BlockUpdate(isBlocked: block))
                .eq("id", value: driverId)
                .execute()
            await fetchDrivers()
        } catch {
            print("Owner: Error blocking driver: \(error)")
        }
    }

    private func blockRestaurant(_ restaurantId: UUID) async {
        do {
            struct BlockUpdate: Codable {
                let isBlocked: Bool
                enum CodingKeys: String, CodingKey {
                    case isBlocked = "is_blocked"
                }
            }
            try await supabaseClient
                .from("restaurants")
                .update(BlockUpdate(isBlocked: true))
                .eq("id", value: restaurantId)
                .execute()
            await fetchRestaurants()
        } catch {
            print("Owner: Error blocking restaurant: \(error)")
        }
    }
}
