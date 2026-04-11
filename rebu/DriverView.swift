import SwiftUI
import UIKit

struct DriverView: View {



    @EnvironmentObject var orderStore: OrderStore

    private var readyOrders: [Order] {

        orderStore.orders.filter { $0.status == .ready }

    }



    private var activeOrder: Order? {

        orderStore.orders.first {

            $0.status == .pending || $0.status == .pickedUp

        }

    }

    var body: some View {



        

        VStack(spacing: 20) {



            Text("Driver")

                .font(.largeTitle)

                .bold()



            // =========================

            // ACTIVE ORDER

            // =========================

            if let order = activeOrder {



                Divider()



                Text(order.restaurantName)

                    .font(.headline)



                

                Text("Status: \(order.status.rawValue)")



                // ---- PICKED UP ----

                if order.status == .pending {

                    Button("Picked Up") {
                        Task {
                            await orderStore.updateStatus(
                                for: order.id,
                                to: .pickedUp
                            )
                        }
                    }

                    .buttonStyle(.borderedProminent)

                }



                // ---- DELIVERED ----

                if order.status == .pickedUp {

                    Divider()



                    Text("Customer")

                        .font(.headline)



                    Text("Address: \(order.customerAddress)")



                    Button("Delivered") {
                        Task {
                            await orderStore.updateStatus(
                                for: order.id,
                                to: .delivered
                            )
                        }
                    }

                    .buttonStyle(.borderedProminent)



                    Button("Call client") {

                        if let url = URL(string: "tel://\(order.customerPhone)") {

                            UIApplication.shared.open(url)

                        }

                    }

                }



            }

            // =========================

            // NO ACTIVE ORDER → READY ORDERS

            // =========================

            else {



                if readyOrders.isEmpty {

                    Text("No READY orders available")

                        .foregroundColor(.gray)

                } else {



                    Divider()



                    let order = readyOrders[0]



                    Text(order.restaurantName)

                        .font(.headline)

                    Text("Payout: $\(String(format: "%.2f", order.total))")

                        .foregroundColor(.gray)

                    Button("Accept Order") {
                        Task {
                            await orderStore.updateStatus(
                                for: order.id,
                                to: .pending
                            )
                        }
                    }

                    .buttonStyle(.borderedProminent)

                }

            }

        }

        .padding()
        .task {
            await orderStore.fetchOrders()
        }

    }

}


