import SwiftUI
import MapKit
import CoreLocation
import Combine
import Supabase

// MARK: - Restaurant data with optional coordinates for map

struct RestaurantData: Identifiable {
    let id: Int
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Location Manager (centers map on real user location)

final class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var userLocation: CLLocation?
    private var manager: CLLocationManager?

    func start() {
        let mgr = CLLocationManager()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        mgr.requestWhenInUseAuthorization()
        self.manager = mgr
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            userLocation = loc
            manager.stopUpdatingLocation()
        }
    }
}

struct ClientView: View {

    @ObservedObject var orderStore: OrderStore
    @StateObject private var locationHelper = LocationHelper()

    // ===== ACCOUNT (PERSISTENT — collected at order time, not at launch) =====
    @State private var firstName: String = UserDefaults.standard.string(forKey: "firstName") ?? ""
    @State private var lastName: String = UserDefaults.standard.string(forKey: "lastName") ?? ""
    @State private var phoneNumber: String = UserDefaults.standard.string(forKey: "phoneNumber") ?? ""
    @State private var deliveryAddress: String = UserDefaults.standard.string(forKey: "deliveryAddress") ?? ""

    // ===== MAP & DATA =====
    @State private var restaurants: [RestaurantData] = []
    @State private var searchText: String = ""
    @State private var activeClientOrder: Order? = nil
    @State private var selectedRestaurant: RestaurantData? = nil
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    )
    @State private var showOrderConfirmation: Bool = false
    @State private var orderPlacedThisSession: Bool = false

    private let orderRefreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var filteredRestaurants: [RestaurantData] {
        if searchText.isEmpty { return restaurants }
        return restaurants.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {

        VStack(spacing: 0) {

            // ===== ACTIVE ORDER TRACKING =====
            if orderPlacedThisSession, let order = activeClientOrder {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: statusIcon(for: order.status))
                        .font(.system(size: 56))
                        .foregroundColor(statusColor(for: order.status))

                    Text(statusTitle(for: order.status))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(statusMessage(for: order.status))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Restaurant")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(order.restaurantName)
                                .fontWeight(.medium)
                        }
                        HStack {
                            Text("Status")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(order.status.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(statusColor(for: order.status).opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    if order.status == .delivered {
                        Button("Done") {
                            activeClientOrder = nil
                            orderPlacedThisSession = false
                        }
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    Spacer()
                }
            }

            // ===== RESTAURANT MENU (state-based navigation) =====
            else if let restaurant = selectedRestaurant {
                // Back button to return to map
                HStack {
                    Button {
                        selectedRestaurant = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                RestaurantMenuView(
                    restaurantId: restaurant.id,
                    restaurantName: restaurant.name,
                    restaurantAddress: restaurant.address,
                    customerName: "\(firstName) \(lastName)",
                    customerAddress: deliveryAddress,
                    customerPhone: phoneNumber,
                    distanceMiles: estimatedDistance(for: restaurant),
                    onOrderPlaced: {
                        selectedRestaurant = nil
                        orderPlacedThisSession = true
                        Task { await fetchActiveOrder() }
                    }
                )
            }

            // ===== MAP + RESTAURANTS (no login gate — Apple guideline) =====
            else {
                // Map with search overlay
                ZStack(alignment: .top) {
                    Map(position: $cameraPosition) {
                        UserAnnotation()
                        ForEach(filteredRestaurants) { restaurant in
                            if let coord = restaurant.coordinate {
                                Marker(restaurant.name, coordinate: coord)
                                    .tint(.red)
                            }
                        }
                    }
                    .mapStyle(.standard(showsTraffic: false))
                    .frame(height: 280)

                    // Search bar overlay
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search restaurants", text: $searchText)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // Restaurant list
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        Text("Restaurants")
                            .font(.headline)
                            .padding(.top, 8)

                        if filteredRestaurants.isEmpty {
                            Text("No restaurants found")
                                .foregroundColor(.gray)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(filteredRestaurants) { restaurant in
                                Button {
                                    selectedRestaurant = restaurant
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(restaurant.name)
                                                .font(.body)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                            Text(restaurant.address)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        let dist = estimatedDistance(for: restaurant)
                                        if dist > 0 {
                                            Text(String(format: "%.1f mi", dist))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                            .font(.caption)
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.08))
                                    .cornerRadius(10)
                                }
                            }
                        }

                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            locationHelper.start()
        }
        .task {
            await fetchRestaurants()
        }
        .onChange(of: locationHelper.userLocation) { _, newLocation in
            if let loc = newLocation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: loc.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                    )
                )
            }
        }
        .onReceive(orderRefreshTimer) { _ in
            if orderPlacedThisSession, activeClientOrder != nil {
                Task { await fetchActiveOrder() }
            }
        }
        .alert("Order Placed!", isPresented: $showOrderConfirmation) {
            Button("OK", role: .cancel) {
                Task { await fetchActiveOrder() }
            }
        } message: {
            Text("The restaurant is preparing your order.")
        }
    }

    // MARK: - Helpers

    /// Estimate distance — uses real user location if available.
    /// When location is unavailable, returns 0 so all restaurants are accessible.
    private func estimatedDistance(for restaurant: RestaurantData) -> Double {
        guard let coord = restaurant.coordinate,
              let userLoc = locationHelper.userLocation else {
            return 0.0 // location unknown — treat all restaurants as available
        }
        let restaurantLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return DeliveryPricing.distanceInMiles(from: userLoc, to: restaurantLocation)
    }

    // MARK: - Fetch Restaurants from Supabase (only ONLINE)

    private func fetchRestaurants() async {
        do {
            let rows: [RestaurantRow] = try await supabaseClient
                .from("restaurants")
                .select()
                .execute()
                .value

            // Show only restaurants that are online (or where is_online is not set)
            let onlineRows = rows.filter { $0.isOnline != false }

            restaurants = onlineRows.map { row in
                RestaurantData(
                    id: row.id,
                    name: row.name,
                    address: row.address ?? "N/A",
                    latitude: row.latitude,
                    longitude: row.longitude
                )
            }

            // Center map on user location first; fall back to restaurant average
            if locationHelper.userLocation == nil {
                let withCoords = restaurants.compactMap { $0.coordinate }
                if !withCoords.isEmpty {
                    let avgLat = withCoords.map(\.latitude).reduce(0, +) / Double(withCoords.count)
                    let avgLng = withCoords.map(\.longitude).reduce(0, +) / Double(withCoords.count)
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng),
                            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                        )
                    )
                }
            }
        } catch {
            print("Error fetching restaurants: \(error)")
        }
    }

    // MARK: - Fetch Active Order for This Client

    private func fetchActiveOrder() async {
        do {
            let rows: [OrderRow] = try await supabaseClient
                .from("orders")
                .select()
                .in("status", values: [
                    OrderStatus.new.rawValue,
                    OrderStatus.accepted.rawValue,
                    OrderStatus.ready.rawValue,
                    OrderStatus.acceptedByDriver.rawValue,
                    OrderStatus.pickedUp.rawValue
                ])
                .order("id", ascending: false)
                .limit(1)
                .execute()
                .value

            if let row = rows.first {
                // Fetch menu item prices for lookup
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
                    print("Error fetching menu items: \(error)")
                }

                // Fetch restaurant name
                var restaurantName = "Restaurant #\(row.restaurantId ?? 0)"
                if let rId = row.restaurantId {
                    do {
                        let rRows: [RestaurantRow] = try await supabaseClient
                            .from("restaurants")
                            .select()
                            .eq("id", value: rId)
                            .limit(1)
                            .execute()
                            .value
                        if let r = rRows.first {
                            restaurantName = r.name
                        }
                    } catch {
                        print("Error fetching restaurant name: \(error)")
                    }
                }

                // Fetch order items
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
                    print("Error fetching order items: \(error)")
                }

                let itemsTotal = items.reduce(0) { $0 + Double($1.quantity) * $1.price }

                let order = Order(
                    id: row.id,
                    items: items,
                    total: itemsTotal,
                    restaurantName: restaurantName,
                    restaurantAddress: "",
                    customerAddress: row.deliveryAddress ?? "",
                    customerPhone: "",
                    status: OrderStatus(rawValue: row.status) ?? .new,
                    driverId: row.driverId
                )
                activeClientOrder = order
            } else {
                activeClientOrder = nil
            }
        } catch {
            print("Error fetching active order: \(error)")
        }
    }

    // MARK: - Order Status Display Helpers

    private func statusIcon(for status: OrderStatus) -> String {
        switch status {
        case .new: return "clock.fill"
        case .accepted: return "checkmark.circle.fill"
        case .ready: return "bag.fill"
        case .acceptedByDriver: return "car.fill"
        case .pickedUp: return "bicycle"
        case .delivered: return "house.fill"
        }
    }

    private func statusColor(for status: OrderStatus) -> Color {
        switch status {
        case .new: return .orange
        case .accepted: return .green
        case .ready: return .blue
        case .acceptedByDriver: return .purple
        case .pickedUp: return .indigo
        case .delivered: return .green
        }
    }

    private func statusTitle(for status: OrderStatus) -> String {
        switch status {
        case .new: return "Order Placed"
        case .accepted: return "Restaurant Accepted"
        case .ready: return "Order Ready"
        case .acceptedByDriver: return "Driver On The Way"
        case .pickedUp: return "Out for Delivery"
        case .delivered: return "Delivered!"
        }
    }

    private func statusMessage(for status: OrderStatus) -> String {
        switch status {
        case .new: return "Waiting for the restaurant to accept your order."
        case .accepted: return "The restaurant accepted and is preparing your order."
        case .ready: return "Your order is ready! Waiting for a driver."
        case .acceptedByDriver: return "A driver is heading to the restaurant to pick up your order."
        case .pickedUp: return "Your order is on its way to you!"
        case .delivered: return "Your order has been delivered. Enjoy!"
        }
    }
}


