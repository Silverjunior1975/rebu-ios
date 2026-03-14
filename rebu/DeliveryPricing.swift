import Foundation
import CoreLocation

struct DeliveryPricing {

    static let maxServiceDistanceMiles: Double = 6.0
    static let rebuFee: Double = 1.50

    /// Driver payout: $2.50 base + $1.50/mile first 5 miles + $0.50/mile after 5
    static func driverPayout(distanceMiles: Double) -> Double {
        let base = 2.50
        let first5 = min(distanceMiles, 5.0) * 1.50
        let after5 = max(0, distanceMiles - 5.0) * 0.50
        return base + first5 + after5
    }

    /// Total delivery fee (driver payout + REBU fee) — hidden from client
    static func deliveryFee(distanceMiles: Double) -> Double {
        return driverPayout(distanceMiles: distanceMiles) + rebuFee
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
