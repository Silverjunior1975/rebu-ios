import Foundation

/// Stripe configuration for REBU payments.
/// Replace the placeholder keys with your actual Stripe keys.
/// The Stripe iOS SDK must be added via SPM in Xcode:
///   File → Add Package Dependencies → https://github.com/stripe/stripe-ios
///   Select product: StripePaymentSheet
struct StripeConfig {

    // MARK: - Stripe Keys

    /// Your Stripe publishable key (starts with pk_test_ or pk_live_)
    static let publishableKey = "pk_test_YOUR_STRIPE_PUBLISHABLE_KEY"

    // MARK: - Setup

    /// Call this once at app launch (e.g. in rebuApp.init) to configure Stripe SDK.
    /// Only activates when the Stripe SDK is available.
    static func configure() {
        #if canImport(StripePaymentSheet)
        StripeAPI.defaultPublishableKey = publishableKey
        #endif
    }
}
