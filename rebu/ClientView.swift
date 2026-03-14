import SwiftUI
import MapKit
import CoreLocation

// MARK: - Restaurant data with optional coordinates for map

struct RestaurantData: Identifiable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct ClientView: View {

    @ObservedObject var orderStore: OrderStore

    // ===== ACCOUNT (PERSISTENT) =====
    @State private var firstName: String = UserDefaults.standard.string(forKey: "firstName") ?? ""
    @State private var lastName: String = UserDefaults.standard.string(forKey: "lastName") ?? ""
    @State private var phoneNumber: String = UserDefaults.standard.string(forKey: "phoneNumber") ?? ""
    @State private var deliveryAddress: String = UserDefaults.standard.string(forKey: "deliveryAddress") ?? ""
    @State private var isLoggedIn: Bool = UserDefaults.standard.bool(forKey: "isLoggedIn")

    // ===== MAP & DATA =====
    @State private var restaurants: [RestaurantData] = []
    @State private var searchText: String = ""
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    )
    @State private var showOrderConfirmation: Bool = false

    private var filteredRestaurants: [RestaurantData] {
        if searchText.isEmpty { return restaurants }
        return restaurants.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {

        VStack(spacing: 0) {

            // ===== CREATE ACCOUNT =====
            if !isLoggedIn {
                ScrollView {
                    VStack(spacing: 16) {

                        Text("REBU")
                            .font(.largeTitle)
                            .bold()

                        Text("Create your account")
                            .font(.headline)

                        TextField("First name", text: $firstName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Last name", text: $lastName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Phone number", text: $phoneNumber)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.phonePad)

                        TextField("Delivery address", text: $deliveryAddress)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button {
                            saveAccount()
                        } label: {
                            Text("Continue")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(accountFormValid ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(!accountFormValid)
                    }
                    .padding()
                }
            }

            // ===== MAP + RESTAURANTS (logged in) =====
            else {
                // Map with search overlay
                ZStack(alignment: .top) {
                    Map(position: $cameraPosition) {
                        ForEach(filteredRestaurants) { restaurant in
                            if let coord = restaurant.coordinate {
                                Marker(restaurant.name, coordinate: coord)
                                    .tint(.red)
                            }
                        }
                    }
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
                                NavigationLink {
                                    RestaurantMenuView(
                                        restaurantId: restaurant.id,
                                        restaurantName: restaurant.name,
                                        restaurantAddress: restaurant.address,
                                        customerName: "\(firstName) \(lastName)",
                                        customerAddress: deliveryAddress,
                                        customerPhone: phoneNumber,
                                        distanceMiles: estimatedDistance(for: restaurant)
                                    )
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
                                        if dist <= DeliveryPricing.maxServiceDistanceMiles {
                                            Text(String(format: "%.1f mi", dist))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Too far")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                            .font(.caption)
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.08))
                                    .cornerRadius(10)
                                }
                                .disabled(
                                    estimatedDistance(for: restaurant) > DeliveryPricing.maxServiceDistanceMiles
                                )
                            }
                        }

                        Button("Reset account") {
                            resetAccount()
                        }
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .task {
            await fetchRestaurants()
        }
        .alert("Order placed!", isPresented: $showOrderConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The restaurant is preparing your order.")
        }
    }

    // MARK: - Helpers

    private var accountFormValid: Bool {
        !firstName.isEmpty && !lastName.isEmpty &&
        !phoneNumber.isEmpty && !deliveryAddress.isEmpty
    }

    /// Estimate distance — uses coordinates if available, otherwise a default
    private func estimatedDistance(for restaurant: RestaurantData) -> Double {
        guard let coord = restaurant.coordinate else {
            return 3.0 // default estimate when coordinates unavailable
        }
        // Use a fixed reference point (Miami) or user location if available
        let userLocation = CLLocation(latitude: 25.7617, longitude: -80.1918)
        let restaurantLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return DeliveryPricing.distanceInMiles(from: userLocation, to: restaurantLocation)
    }

    private func saveAccount() {
        UserDefaults.standard.set(firstName, forKey: "firstName")
        UserDefaults.standard.set(lastName, forKey: "lastName")
        UserDefaults.standard.set(phoneNumber, forKey: "phoneNumber")
        UserDefaults.standard.set(deliveryAddress, forKey: "deliveryAddress")
        UserDefaults.standard.set(true, forKey: "isLoggedIn")
        isLoggedIn = true
    }

    private func resetAccount() {
        UserDefaults.standard.removeObject(forKey: "firstName")
        UserDefaults.standard.removeObject(forKey: "lastName")
        UserDefaults.standard.removeObject(forKey: "phoneNumber")
        UserDefaults.standard.removeObject(forKey: "deliveryAddress")
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        isLoggedIn = false
    }

    // MARK: - Fetch Restaurants from Supabase

    private func fetchRestaurants() async {
        do {
            let rows: [RestaurantRow] = try await supabaseClient
                .from("restaurants")
                .select()
                .execute()
                .value

            restaurants = rows.map { row in
                RestaurantData(
                    id: row.id,
                    name: row.name,
                    address: row.address ?? "N/A",
                    latitude: row.latitude,
                    longitude: row.longitude
                )
            }

            // Center map on restaurants if coordinates available
            let withCoords = restaurants.compactMap { $0.coordinate }
            if let first = withCoords.first {
                let avgLat = withCoords.map(\.latitude).reduce(0, +) / Double(withCoords.count)
                let avgLng = withCoords.map(\.longitude).reduce(0, +) / Double(withCoords.count)
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng),
                        span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                    )
                )
                _ = first // suppress unused warning
            }
        } catch {
            print("Error fetching restaurants: \(error)")
        }
    }
}


