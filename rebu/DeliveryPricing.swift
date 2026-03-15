import Foundation
import CoreLocation

struct DeliveryPricing {

    static let maxServiceDistanceMiles: Double = 6.0

    /// Driver payout: $2.50 base + $1.50/mile first 5 miles + $0.50/mile after 5
    static func driverPayout(distanceMiles: Double) -> Double {
        let base = 2.50
        let first5 = min(distanceMiles, 5.0) * 1.50
        let after5 = max(0, distanceMiles - 5.0) * 0.50
        return base + first5 + after5
    }

    /// REBU commission: $2.50 minimum + $0.58/mile after the first 2 miles
    static func rebuCommission(distanceMiles: Double) -> Double {
        let base = 2.50
        let mileageCharge = max(0, distanceMiles - 2.0) * 0.58
        return base + mileageCharge
    }

    /// Total delivery fee (driver payout + REBU commission) — hidden from client
    static func deliveryFee(distanceMiles: Double) -> Double {
        return driverPayout(distanceMiles: distanceMiles) + rebuCommission(distanceMiles: distanceMiles)
    }

    /// Whether the restaurant is within the 6-mile service area
    static func isWithinServiceArea(distanceMiles: Double) -> Bool {
        return distanceMiles <= maxServiceDistanceMiles
    }

    /// Distance in miles between two CLLocation points
    static func distanceInMiles(from: CLLocation, to: CLLocation) -> Double {
        let meters = from.distance(from: to)
        return meters / 1609.34
    }

    /// Default delivery fee when distance is unknown (assumes ~3 miles)
    static func defaultDeliveryFee() -> Double {
        return deliveryFee(distanceMiles: 3.0)
    }
}
