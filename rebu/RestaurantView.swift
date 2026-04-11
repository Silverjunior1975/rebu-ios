import SwiftUI
import Combine

struct RestaurantView: View {

    @EnvironmentObject var orderStore: OrderStore

    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {

        NavigationView {

            List {

                ForEach(orderStore.orders.filter {

                    $0.status == .new || $0.status == .accepted || $0.status == .ready

                }) { order in

                    VStack(alignment: .leading, spacing: 8) {



                        Text("Order #\(order.id)")

                            .font(.headline)



                        ForEach(order.items) { item in

                            HStack {

                                Text("\(item.quantity)x \(item.name)")

                                Spacer()

                                Text(String(format: "$%.2f", item.price))

                                    .foregroundColor(.gray)

                            }

                        }



                        Text("Items Total: $\(String(format: "%.2f", order.total))")

                            .bold()



                        Text("Status: \(order.status.rawValue.uppercased())")



                        if order.status == .new {

                            Button("Accept Order") {
                                Task {
                                    await orderStore.updateStatus(
                                        for: order.id,
                                        to: .accepted
                                    )
                                }
                            }

                            .buttonStyle(.borderedProminent)

                        }



                        if order.status == .accepted {

                            Button("Mark as READY") {
                                Task {
                                    await orderStore.updateStatus(
                                        for: order.id,
                                        to: .ready
                                    )
                                }
                            }

                            .buttonStyle(.borderedProminent)

                        }

                        if order.status == .ready {
                            Text("Waiting for driver")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                    }

                    .padding(.vertical, 8)

                }

            }

            .navigationTitle("Restaurant")

        }
        .task {
            await orderStore.fetchOrders()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await orderStore.fetchOrders()
            }
        }

    }

}


