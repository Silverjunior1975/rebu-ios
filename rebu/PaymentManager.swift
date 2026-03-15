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

    // MARK: - Edge Function Request/Response Types

    private struct CreatePaymentIntentRequest: Encodable {
        let amount: Int
        let currency: String
        let customerPhone: String
        let captureMethod: String

        enum CodingKeys: String, CodingKey {
            case amount, currency
            case customerPhone = "customer_phone"
            case captureMethod = "capture_method"
        }
    }

    private struct PaymentIntentResponse: Decodable {
        let clientSecret: String
        let paymentIntentId: String

        enum CodingKeys: String, CodingKey {
            case clientSecret = "client_secret"
            case paymentIntentId = "payment_intent_id"
        }
    }

    private struct CashOutRequest: Encodable {
        let driverId: String
        let amount: Int

        enum CodingKeys: String, CodingKey {
            case driverId = "driver_id"
            case amount
        }
    }

    private struct CashOutResponse: Decodable {
        let success: Bool
    }

    // MARK: - Create PaymentIntent (authorize, do NOT capture yet)

    /// Calls the Supabase Edge Function to create a Stripe PaymentIntent with manual capture.
    /// Returns (clientSecret, paymentIntentId) on success, nil on failure.
    func createPaymentIntent(amount: Double, customerPhone: String) async -> (clientSecret: String, paymentIntentId: String)? {
        isProcessing = true
        errorMessage = nil

        do {
            let request = CreatePaymentIntentRequest(
                amount: Int(amount * 100),
                currency: "usd",
                customerPhone: customerPhone,
                captureMethod: "manual"
            )

            let result: PaymentIntentResponse = try await supabaseClient.functions.invoke(
                "create-payment-intent",
                options: .init(body: request)
            )

            lastPaymentIntentId = result.paymentIntentId
            isProcessing = false
            return (result.clientSecret, result.paymentIntentId)
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
            let request = CashOutRequest(
                driverId: driverId,
                amount: Int(amount * 100)
            )

            let result: CashOutResponse = try await supabaseClient.functions.invoke(
                "driver-cash-out",
                options: .init(body: request)
            )

            if result.success {
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
