import SwiftUI
import MapKit

struct DriverDashboardView: View {

    @EnvironmentObject var orderStore: OrderStore
    @State private var isOnline: Bool = false
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )

    private var activeOrder: Order? {
        orderStore.orders.first {
            $0.status == .acceptedByDriver || $0.status == .pickedUp
        }
    }

    private var readyOrders: [Order] {
        orderStore.orders.filter { $0.status == .ready && $0.driverId == nil }
    }

    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Map
            Map(position: $cameraPosition)
                .frame(height: 220)
                .overlay(alignment: .topTrailing) {
                    // Earnings badge
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Today")
                            .font(.caption2)
                            .foregroundColor(.white)
                        Text(String(format: "$%.2f", orderStore.todayTotal))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(12)
                }

            // MARK: - Online/Offline Toggle
            HStack {
                Circle()
                    .fill(isOnline ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(isOnline ? "Online" : "Offline")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Toggle("", isOn: $isOnline)
                    .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isOnline ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))

            // MARK: - Content
            if !isOnline {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Go online to start delivering")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {

                        // Active order
                        if let order = activeOrder {
                            activeOrderCard(order)
                        }
                        // Available deliveries
                        else if readyOrders.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 36))
                                    .foregroundColor(.gray)
                                Text("No deliveries available")
                                    .foregroundColor(.gray)
                                Text("Waiting for orders...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 40)
                        } else {
                            Text("Available Deliveries")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Show only the first ready order (one at a time)
                            let order = readyOrders[0]
                            deliveryCard(order)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Driver")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await orderStore.fetchOrders()
        }
        .onReceive(refreshTimer) { _ in
            if isOnline {
                Task {
                    await orderStore.fetchOrders()
                }
            }
        }
    }

    // MARK: - Estimated Driver Payout

    /// Estimate driver payout from order data (without needing stored distance).
    /// deliveryFee = driverPayout + rebuCommission. We derive deliveryFee from order total minus items.
    private func estimatedDriverPayout(for order: Order) -> Double {
        let itemsTotal = order.items.reduce(0.0) { $0 + Double($1.quantity) * $1.price }
        let deliveryFee = max(0, order.total - itemsTotal)
        // deliveryFee = driverPayout + rebuCommission
        // rebuCommission minimum is $2.50, so driver gets at least deliveryFee - rebuCommission
        // Approximate: subtract minimum REBU commission
        return max(2.50, deliveryFee - 2.50)
    }

    // MARK: - Delivery Card (available order — driver has NOT accepted yet)

    private func deliveryCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.restaurantName)
                        .font(.headline)
                    Text(order.restaurantAddress)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Est. Payout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "$%.2f", estimatedDriverPayout(for: order)))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }

            // Before accepting: driver does NOT see customer address
            Button {
                Task {
                    await orderStore.updateStatus(for: order.id, to: .acceptedByDriver)
                }
            } label: {
                Text("Accept Delivery")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.06))
        .cornerRadius(14)
    }

    // MARK: - Active Order Card

    private func activeOrderCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("Active Delivery")
                    .font(.headline)
                Spacer()
                Text(order.status.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(6)
            }

            Divider()

            // Restaurant info (always visible after accepting)
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading) {
                    Text("Pickup")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(order.restaurantName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(order.restaurantAddress)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            // Customer address revealed ONLY after picked up
            if order.status == .pickedUp {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Deliver to")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(order.customerAddress)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }

            // Action buttons
            if order.status == .acceptedByDriver {
                Text("Head to restaurant for pickup")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                Button {
                    Task {
                        await orderStore.updateStatus(for: order.id, to: .pickedUp)
                    }
                } label: {
                    HStack {
                        Image(systemName: "bag.fill")
                        Text("Picked Up")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }

            if order.status == .pickedUp {
                Button {
                    Task {
                        await orderStore.updateStatus(for: order.id, to: .delivered)
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Delivered")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Button {
                    orderStore.callClient(phone: order.customerPhone)
                } label: {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Call Customer")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.06))
        .cornerRadius(14)
    }
}
