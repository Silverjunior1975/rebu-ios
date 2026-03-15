import Foundation
import Combine
import Supabase

/// Manages Stripe payment operations for REBU.
/// All server-side Stripe calls go through Supabase Edge Functions.
/// The Stripe iOS SDK is optional — if not installed, payment collection is skipped
/// and orders are placed without payment (for development/testing).
@MainActor
class PaymentManager: ObservableObject {

    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var lastPaymentIntentId: String?

    // MARK: - Create PaymentIntent (authorize, do NOT capture yet)

    /// Calls the Supabase Edge Function to create a Stripe PaymentIntent with manual capture.
    /// Returns (clientSecret, paymentIntentId) on success, nil on failure.
    func createPaymentIntent(amount: Double, customerPhone: String) async -> (clientSecret: String, paymentIntentId: String)? {
        isProcessing = true
        errorMessage = nil

        do {
            let body: [String: Any] = [
                "amount": Int(amount * 100), // Stripe uses cents
                "currency": "usd",
                "customer_phone": customerPhone,
                "capture_method": "manual"
            ]
            let bodyData = try JSONSerialization.data(withJSONObject: body)

            let response = try await supabaseClient.functions.invoke(
                "create-payment-intent",
                options: .init(body: bodyData)
            )

            if let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
               let clientSecret = json["client_secret"] as? String,
               let paymentIntentId = json["payment_intent_id"] as? String {
                lastPaymentIntentId = paymentIntentId
                isProcessing = false
                return (clientSecret, paymentIntentId)
            } else {
                errorMessage = "Invalid response from payment server"
            }
        } catch {
            errorMessage = "Payment setup failed: \(error.localizedDescription)"
            print("PaymentManager.createPaymentIntent error: \(error)")
        }

        isProcessing = false
        return nil
    }

    // MARK: - Update Order with PaymentIntent ID

    /// After placing the order, link the payment to the order record in Supabase.
    func linkPaymentToOrder(customerPhone: String, paymentIntentId: String) async {
        do {
            // Find the most recent order for this customer
            struct OrderIdRow: Codable {
                let id: UUID
            }

            let rows: [OrderIdRow] = try await supabaseClient
                .from("orders")
                .select("id")
                .eq("customer_phone", value: customerPhone)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let orderId = rows.first?.id else {
                print("PaymentManager: Could not find order to link payment")
                return
            }

            struct PaymentUpdate: Codable {
                let paymentIntentId: String

                enum CodingKeys: String, CodingKey {
                    case paymentIntentId = "payment_intent_id"
                }
            }

            try await supabaseClient
                .from("orders")
                .update(PaymentUpdate(paymentIntentId: paymentIntentId))
                .eq("id", value: orderId)
                .execute()

        } catch {
            print("PaymentManager.linkPaymentToOrder error: \(error)")
        }
    }

    // MARK: - Driver Cash Out

    /// Initiates a payout to the driver's bank account via Stripe Connect.
    /// Calls the Supabase Edge Function which handles the Stripe payout.
    func cashOut(driverId: String, amount: Double) async -> Bool {
        isProcessing = true
        errorMessage = nil

        do {
            let body: [String: Any] = [
                "driver_id": driverId,
                "amount": Int(amount * 100) // cents
            ]
            let bodyData = try JSONSerialization.data(withJSONObject: body)

            let response = try await supabaseClient.functions.invoke(
                "driver-cash-out",
                options: .init(body: bodyData)
            )

            if let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
               let success = json["success"] as? Bool, success {
                isProcessing = false
                return true
            } else {
                errorMessage = "Cash out failed. Please try again."
            }
        } catch {
            errorMessage = "Cash out error: \(error.localizedDescription)"
            print("PaymentManager.cashOut error: \(error)")
        }

        isProcessing = false
        return false
    }

    // MARK: - Stripe SDK Payment Sheet (requires Stripe iOS SDK)

    /// Returns true if the Stripe SDK is available for payment collection.
    var isStripeSDKAvailable: Bool {
        #if canImport(StripePaymentSheet)
        return true
        #else
        return false
        #endif
    }
}
