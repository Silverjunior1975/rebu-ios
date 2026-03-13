import SwiftUI



struct RestaurantView: View {

    @EnvironmentObject var orderStore: OrderStore



    var body: some View {

        NavigationView {

            List {

                ForEach(orderStore.orders.filter {

                    $0.status == .new || $0.status == .accepted

                }) { order in

                    VStack(alignment: .leading, spacing: 8) {



                        Text("Order #\(order.id.uuidString.prefix(8))")

                            .font(.headline)



                        ForEach(order.items) { item in

                            HStack {

                                Text("\(item.quantity)x \(item.name)")

                                Spacer()

                                Text(String(format: "$%.2f", item.price))

                                    .foregroundColor(.gray)

                            }

                        }



                        Text("Total: $\(String(format: "%.2f", order.total))")

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

                    }

                    .padding(.vertical, 8)

                }

            }

            .navigationTitle("Restaurant")

        }
        .task {
            await orderStore.fetchOrders()
        }

    }

}


