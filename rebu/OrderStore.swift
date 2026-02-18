import Foundation

import Combine
import UIKit


class OrderStore: ObservableObject {



    @Published var orders: [Order] = []
    var readyOrders: [Order] {

        orders.filter {

            $0.status == .ready && $0.driverId == nil

        }

    }
    func pickUpOrder(orderID: UUID) {

        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }

        orders[index].status = .pickedUp

    }



    func deliverOrder(orderID: UUID) {

        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }

        orders[index].status = .delivered

    }

    var todayTotal: Double {

        orders

            .filter { $0.status == .delivered }

            .reduce(0) { $0 + $1.total }

    }



    func addOrder(_ order: Order) {

        orders.append(order)

    }



    func updateStatus(for orderID: UUID, to newStatus: OrderStatus) {

        if let index = orders.firstIndex(where: { $0.id == orderID }) {

            orders[index].status = newStatus

        }

    }



    func acceptOrder(orderID: UUID, driverID: UUID) {

        guard let index = orders.firstIndex(where: {

            $0.id == orderID && $0.driverId == nil

        }) else { return }



        orders[index].driverId = driverID

        orders[index].status = .accepted

    }



    func markDelivered(orderID: UUID) {

        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }

        orders[index].status = .delivered

    }
    func callClient(phone: String) {

        let cleaned = phone.replacingOccurrences(of: " ", with: "")

        if let url = URL(string: "tel://\(cleaned)") {

            UIApplication.shared.open(url)

        }

    }


}


