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



    private let restaurants: [Restaurant] = [

        Restaurant(

            id: UUID(),

            name: "Burger House",

            products: [

                Product(id: UUID(), name: "Cheeseburger", price: 10.00),

                Product(id: UUID(), name: "Fries", price: 4.50)

            ]

        )

    ]



    @State private var selectedRestaurant: Restaurant?

    @State private var cart: [Product] = []



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

                                placeOrder(restaurant: restaurant)

                            }

                            .padding()

                            .frame(maxWidth: .infinity)

                            .background(Color.blue)

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



    private func placeOrder(restaurant: Restaurant) {

        let order = Order(

            id: UUID(),

            items: cart.map {

                OrderItem(

                    name: $0.name,

                    quantity: 1,

                    price: $0.price

                )

            },

            total: cart.reduce(0) { $0 + $1.price },

            restaurantName: restaurant.name,

            restaurantAddress: "N/A",

            customerAddress: "\(firstName) \(lastName), \(phoneNumber), \(deliveryAddress)",
            customerPhone: phoneNumber,
            status: .new,
            driverId: nil
        )




        orderStore.orders.append(order)

        cart = []

        selectedRestaurant = nil

    }

}


