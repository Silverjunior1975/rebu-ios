import SwiftUI
import MapKit
import CoreLocation
import Combine
import Supabase

struct DriverDashboardView: View {

    @EnvironmentObject var orderStore: OrderStore
    @State private var isOnline: Bool = false
    @State private var showCashOut: Bool = false
    @State private var cashOutSuccess: Bool = false
    @State private var cashOutError: String?
    @State private var acceptError: String?
    @StateObject private var paymentManager = PaymentManager()
    @StateObject private var locationHelper = LocationHelper()
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )

    /// Stable driver ID stored per device (same pattern as client account)
    private var driverId: UUID {
        if let stored = UserDefaults.standard.string(forKey: "driverId"),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let newId = UUID()
        UserDefaults.standard.set(newId.uuidString, forKey: "driverId")
        return newId
    }

    /// Active order for THIS driver only (enforces one active order per driver)
    private var activeOrder: Order? {
        orderStore.orders.first {
            ($0.status == .acceptedByDriver || $0.status == .pickedUp) &&
            $0.driverId == driverId
        }
    }

    private var readyOrders: [Order] {
        orderStore.orders.filter { $0.status == .ready && $0.driverId == nil }
    }

    /// Earnings for THIS driver only
    private var driverEarnings: Double {
        orderStore.orders
            .filter { $0.status == .delivered && $0.driverId == driverId }
            .reduce(0.0) { total, order in
                total + estimatedDriverPayout(for: order)
            }
    }

    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Map
            Map(position: $cameraPosition) {
                UserAnnotation()
            }
            .mapStyle(.standard(showsTraffic: false))
            .frame(height: 220)
                .overlay(alignment: .topTrailing) {
                    // Earnings badge (tappable for cash out)
                    Button {
                        showCashOut = true
                    } label: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Today")
                                .font(.caption2)
                                .foregroundColor(.white)
                            Text(String(format: "$%.2f", driverEarnings))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(12)
                    }
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
                    .onChange(of: isOnline) { _, newValue in
                        Task { await setDriverOnline(newValue) }
                    }
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
        .onAppear {
            locationHelper.start()
        }
        .onChange(of: locationHelper.userLocation) { _, newLocation in
            if let loc = newLocation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: loc.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                )
            }
        }
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
        .sheet(isPresented: $showCashOut) {
            cashOutSheet
        }
        .alert("Cash Out Successful", isPresented: $cashOutSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your earnings have been sent to your bank account.")
        }
    }

    // MARK: - Cash Out Sheet

    private var cashOutSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "banknote")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Your Earnings")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String(format: "$%.2f", driverEarnings))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.green)

                if driverEarnings > 0 {
                    Button {
                        Task {
                            let success = await paymentManager.cashOut(
                                driverId: driverId.uuidString,
                                amount: driverEarnings
                            )
                            if success {
                                showCashOut = false
                                cashOutSuccess = true
                            } else {
                                cashOutError = paymentManager.errorMessage ?? "Cash out failed"
                            }
                        }
                    } label: {
                        HStack {
                            if paymentManager.isProcessing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Cash Out")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(paymentManager.isProcessing ? Color.gray : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(paymentManager.isProcessing)
                    .padding(.horizontal)
                } else {
                    Text("Complete deliveries to earn money")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                if let error = cashOutError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Cash Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showCashOut = false }
                }
            }
        }
    }

    // MARK: - Driver Online/Offline in Supabase

    private func setDriverOnline(_ online: Bool) async {
        do {
            try await supabaseClient
                .from("drivers")
                .upsert(DriverUpsert(id: driverId, isOnline: online))
                .execute()
        } catch {
            print("Driver: Error updating online status: \(error)")
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
            if let error = acceptError {
                Text(error)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
            }

            Button {
                print("ACCEPT DELIVERY TAPPED for order \(order.id)")
                Task {
                    acceptError = nil
                    let success = await orderStore.acceptOrder(orderID: order.id, driverID: driverId)
                    if !success {
                        acceptError = "Failed to accept delivery. Please try again."
                    }
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
