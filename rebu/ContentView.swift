import SwiftUI



struct ContentView: View {



    @EnvironmentObject var orderStore: OrderStore

    @State private var appRole: AppRole? = nil



    var body: some View {

        NavigationView {

            VStack(spacing: 20) {
                if appRole != nil {

                    Button("Back") {

                        appRole = nil

                    }

                }


                if appRole == nil {

                    Text("REBU")

                        .font(.largeTitle)

                        .bold()



                    Button("Client") {

                        appRole = .client

                    }



                    Button("Restaurant") {

                        appRole = .restaurant

                    }



                    Button("Driver") {

                        appRole = .driver

                    }



                } else if appRole == .client {

                    ClientView(orderStore: orderStore)



                } else if appRole == .restaurant {

                    RestaurantView()



                } else if appRole == .driver {

                    DriverDashboardView()

                }

            }

            .navigationTitle("REBU")

        }

    }

}



enum AppRole {

    case client

    case restaurant

    case driver

}


