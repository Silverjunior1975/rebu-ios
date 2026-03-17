import SwiftUI
import Supabase

struct RestaurantMenuView: View {

    @EnvironmentObject var orderStore: OrderStore

    let restaurantId: Int
    let restaurantName: String
    let restaurantAddress: String
    let customerName: String
    let customerAddress: String
    let customerPhone: String
    let distanceMiles: Double
    var onOrderPlaced: (() -> Void)? = nil

    @State private var menuItems: [Product] = []
    @State private var cart: [Product] = []
    @State private var menuIdMap: [UUID: Int] = [:] // Product.id → menu_items.id
    @State private var isPlacingOrder: Bool = false
    @State private var showOrderConfirmation: Bool = false
    @State private var isLoading: Bool = true
    @State private var paymentError: String?
    @State private var noDriversAvailable: Bool = false
    @StateObject private var paymentManager = PaymentManager()

    // Editable delivery info (initialized from passed-in values, editable by user)
    @State private var editableName: String = ""
    @State private var editableAddress: String = ""
    @State private var editablePhone: String = ""

    @Environment(\.dismiss) private var dismiss

    private var itemsTotal: Double {
        cart.reduce(0) { $0 + $1.price }
    }

    private var deliveryFee: Double {
        DeliveryPricing.deliveryFee(distanceMiles: distanceMiles)
    }

    private var finalTotal: Double {
        itemsTotal + deliveryFee
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Restaurant header
                VStack(alignment: .leading, spacing: 4) {
                    Text(restaurantName)
                        .font(.title2)
                        .bold()

                    Text(restaurantAddress)
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Text(String(format: "%.1f miles away", distanceMiles))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Menu items
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading menu...")
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else if menuItems.isEmpty {
                    HStack {
                        Spacer()
                        Text("No menu items available")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else {
                    Text("Menu")
                        .font(.headline)

                    ForEach(menuItems) { product in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.name)
                                    .font(.body)
                                Text(String(format: "$%.2f", product.price))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button {
                                cart.append(product)
                            } label: {
                                Text("Add")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(10)
                    }
                }

                // Cart section
                if !cart.isEmpty {
                    Divider()

                    Text("Your Order")
                        .font(.headline)

                    ForEach(Array(cartSummary.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text("\(entry.quantity)x \(entry.name)")
                            Spacer()
                            Text(String(format: "$%.2f", entry.subtotal))
                                .foregroundColor(.gray)
                        }
                    }

                    Divider()

                    // Client sees only the final total (delivery included internally)
                    HStack {
                        Text("Total")
                            .fontWeight(.bold)
                            .font(.title3)
                        Spacer()
                        Text(String(format: "$%.2f", finalTotal))
                            .fontWeight(.bold)
                            .font(.title3)
                    }

                    // Delivery info (editable inline)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Delivery Info")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        TextField("Your name", text: $editableName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Delivery address", text: $editableAddress)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Phone number", text: $editablePhone)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.phonePad)
                    }
                    .padding(.vertical, 4)

                    if noDriversAvailable {
                        Text("No drivers available right now")
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                    }

                    if let error = paymentError {
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
                        Task {
                            await placeOrder()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isPlacingOrder {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Place Order")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(canPlaceOrder ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canPlaceOrder)

                    Button("Clear Cart") {
                        cart = []
                    }
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Menu")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize editable fields from passed-in values
            if editableName.isEmpty { editableName = customerName }
            if editableAddress.isEmpty { editableAddress = customerAddress }
            if editablePhone.isEmpty { editablePhone = customerPhone }
        }
        .task {
            await fetchMenuItems()
            await checkDriverAvailability()
        }
        .alert("Order Placed!", isPresented: $showOrderConfirmation) {
            Button("OK", role: .cancel) {
                if let callback = onOrderPlaced {
                    callback()
                } else {
                    dismiss()
                }
            }
        } message: {
            Text("The restaurant is preparing your order.")
        }
    }

    // MARK: - Validation

    private var canPlaceOrder: Bool {
        !isPlacingOrder && !noDriversAvailable &&
        !editableName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !editableAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !editablePhone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Cart Summary

    private struct CartEntry {
        let name: String
        let quantity: Int
        let subtotal: Double
    }

    private var cartSummary: [CartEntry] {
        var dict: [String: (quantity: Int, subtotal: Double)] = [:]
        for item in cart {
            if let existing = dict[item.name] {
                dict[item.name] = (existing.quantity + 1, existing.subtotal + item.price)
            } else {
                dict[item.name] = (1, item.price)
            }
        }
        return dict.map { CartEntry(name: $0.key, quantity: $0.value.quantity, subtotal: $0.value.subtotal) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Fetch Menu Items from Supabase

    private func fetchMenuItems() async {
        do {
            let rows: [MenuItemRow] = try await supabaseClient
                .from("menu_items")
                .select()
                .eq("restaurant_id", value: restaurantId)
                .execute()
                .value

            menuItems = rows.map { row in
                let product = Product(id: UUID(), name: row.name, price: row.price)
                menuIdMap[product.id] = row.id
                return product
            }
            isLoading = false
        } catch {
            print("Error fetching menu items: \(error)")
            isLoading = false
        }
    }

    // MARK: - Check Driver Availability

    private func checkDriverAvailability() async {
        do {
            let drivers: [DriverRow] = try await supabaseClient
                .from("drivers")
                .select()
                .eq("is_online", value: true)
                .execute()
                .value
            noDriversAvailable = drivers.isEmpty
        } catch {
            // If drivers table doesn't exist yet, allow order (graceful degradation)
            print("Driver availability check skipped: \(error)")
            noDriversAvailable = false
        }
    }

    // MARK: - Place Order (with Stripe payment)

    private func placeOrder() async {
        isPlacingOrder = true
        paymentError = nil

        // Re-check driver availability right before placing
        await checkDriverAvailability()
        if noDriversAvailable {
            isPlacingOrder = false
            return
        }

        let finalName = editableName.trimmingCharacters(in: .whitespaces)
        let finalAddress = editableAddress.trimmingCharacters(in: .whitespaces)
        let finalPhone = editablePhone.trimmingCharacters(in: .whitespaces)

        // Save for future use
        UserDefaults.standard.set(finalName, forKey: "firstName")
        UserDefaults.standard.set(finalAddress, forKey: "deliveryAddress")
        UserDefaults.standard.set(finalPhone, forKey: "phoneNumber")

        // Step 1: Try to create PaymentIntent (authorize, not capture)
        var paymentIntentId: String?
        if let result = await paymentManager.createPaymentIntent(
            amount: finalTotal,
            customerPhone: finalPhone
        ) {
            paymentIntentId = result.paymentIntentId
            // Payment authorized — will be captured when restaurant accepts
        } else if let error = paymentManager.errorMessage {
            // Edge Function not deployed or Stripe not configured — proceed without payment
            print("Payment setup skipped: \(error)")
        }

        // Step 2: Place order in Supabase
        // Aggregate cart by menu_item_id
        var menuQuantities: [Int: Int] = [:]
        for product in cart {
            if let menuId = menuIdMap[product.id] {
                menuQuantities[menuId, default: 0] += 1
            }
        }
        let orderItems = menuQuantities.map { (menuItemId: $0.key, quantity: $0.value) }

        let success = await orderStore.placeOrder(
            customerId: nil,
            restaurantId: restaurantId,
            deliveryAddress: finalAddress,
            items: orderItems
        )

        // Step 3: Link payment to order if PaymentIntent was created
        if success, let piId = paymentIntentId {
            await paymentManager.linkPaymentToOrder(
                customerPhone: finalPhone,
                paymentIntentId: piId
            )
        }

        isPlacingOrder = false

        guard success else {
            paymentError = "Failed to place order. Please try again."
            return
        }

        cart = []
        showOrderConfirmation = true
    }
}


