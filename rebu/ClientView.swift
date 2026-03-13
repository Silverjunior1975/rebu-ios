import SwiftUI



struct ClientView: View {



    @ObservedObject var orderStore: OrderStore



    // ===== ACCOUNT (PERSISTENT) =====

    @State private var firstName: String = UserDefaults.standard.string(forKey: "firstName") ?? ""

    @State private var lastName: String = UserDefaults.standard.string(forKey: "lastName") ?? ""

    @State private var phoneNumber: String = UserDefaults.standard.string(forKey: "phoneNumber") ?? ""

    @State private var deliveryAddress: String = UserDefaults.standard.string(forKey: "deliveryAddress") ?? ""

    @State private var isLoggedIn: Bool = UserDefaults.standard.bool(forKey: "isLoggedIn")



    // ===== DATA =====

    private let deliveryFee: Double = 4.00

    @State private var restaurants: [Restaurant] = []

    // Default menu items (until a products table is added to Supabase)
    private let defaultProducts: [Product] = [
        Product(id: UUID(), name: "Cheeseburger", price: 10.00),
        Product(id: UUID(), name: "Fries", price: 4.50)
    ]

    @State private var selectedRestaurant: Restaurant?

    @State private var cart: [Product] = []

    @State private var isPlacingOrder: Bool = false



    var body: some View {

        ScrollView {

            VStack(spacing: 20) {



                Text("Client")

                    .font(.largeTitle)

                    .bold()



                // ===== CREATE ACCOUNT =====

                if !isLoggedIn {

                    VStack(spacing: 12) {

                        Text("Create account")

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



                        Button("Continue") {

                            saveAccount()

                        }

                        .disabled(

                            firstName.isEmpty ||

                            lastName.isEmpty ||

                            phoneNumber.isEmpty ||

                            deliveryAddress.isEmpty

                        )

                        .padding()

                        .frame(maxWidth: .infinity)

                        .background(

                            (firstName.isEmpty ||

                             lastName.isEmpty ||

                             phoneNumber.isEmpty ||

                             deliveryAddress.isEmpty)

                            ? Color.gray : Color.blue

                        )

                        .foregroundColor(.white)

                        .cornerRadius(8)

                    }

                }



                // ===== RESTAURANTS =====

                if isLoggedIn && selectedRestaurant == nil {

                    VStack(alignment: .leading, spacing: 12) {

                        Text("Restaurants")

                            .font(.headline)



                        ForEach(restaurants) { restaurant in

                            Button {

                                selectedRestaurant = restaurant

                                cart = []

                            } label: {

                                Text(restaurant.name)

                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    .padding()

                                    .background(Color.gray.opacity(0.1))

                                    .cornerRadius(8)

                            }

                        }



                        // OPTIONAL logout (pentru test)

                        Button("Reset account") {

                            resetAccount()

                        }

                        .font(.footnote)

                        .foregroundColor(.red)

                        .padding(.top)

                    }

                }



                // ===== PRODUCTS + CART =====

                if let restaurant = selectedRestaurant {

                    VStack(alignment: .leading, spacing: 12) {



                        Text(restaurant.name)

                            .font(.headline)



                        ForEach(restaurant.products) { product in

                            HStack {

                                VStack(alignment: .leading) {

                                    Text(product.name)

                                    Text(String(format: "$%.2f", product.price))

                                        .foregroundColor(.gray)

                                }



                                Spacer()



                                Button("Add") {

                                    cart.append(product)

                                }

                            }

                            .padding()

                            .background(Color.gray.opacity(0.1))

                            .cornerRadius(8)

                        }



                        if !cart.isEmpty {

                            Divider()



                            VStack(spacing: 6) {

                                row("Items", itemsTotal)

                                row("Delivery fee", deliveryFee)

                                Divider()

                                row("Total", finalTotal, bold: true)

                            }



                            Button("Place Order") {
                                Task {
                                    await placeOrder(restaurant: restaurant)
                                }
                            }
                            .disabled(isPlacingOrder)

                            .padding()

                            .frame(maxWidth: .infinity)

                            .background(isPlacingOrder ? Color.gray : Color.blue)

                            .foregroundColor(.white)

                            .cornerRadius(8)



                            Text("Payments are currently unavailable.")

                                .font(.footnote)

                                .foregroundColor(.gray)

                        }



                        Button("Back to restaurants") {

                            selectedRestaurant = nil

                            cart = []

                        }

                        .padding(.top)

                    }

                }

            }

            .padding()

        }
        .task {
            await fetchRestaurants()
        }

    }



    // ===== HELPERS =====

    private func row(_ title: String, _ value: Double, bold: Bool = false) -> some View {

        HStack {

            Text(title)

                .fontWeight(bold ? .bold : .regular)

            Spacer()

            Text(String(format: "$%.2f", value))

                .fontWeight(bold ? .bold : .regular)

        }

    }



    private var itemsTotal: Double {

        cart.reduce(0) { $0 + $1.price }

    }



    private var finalTotal: Double {

        itemsTotal + deliveryFee

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
                Restaurant(
                    id: row.id,
                    name: row.name,
                    address: row.address ?? "N/A",
                    products: defaultProducts
                )
            }
        } catch {
            print("Error fetching restaurants: \(error)")
        }
    }

    // MARK: - Place Order via Supabase

    private func placeOrder(restaurant: Restaurant) async {
        isPlacingOrder = true

        let success = await orderStore.placeOrder(
            restaurantId: restaurant.id,
            restaurantName: restaurant.name,
            restaurantAddress: restaurant.address,
            customerName: "\(firstName) \(lastName)",
            customerAddress: deliveryAddress,
            customerPhone: phoneNumber,
            items: cart,
            deliveryFee: deliveryFee
        )

        isPlacingOrder = false

        if success {
            cart = []
            selectedRestaurant = nil
        }
    }

}
