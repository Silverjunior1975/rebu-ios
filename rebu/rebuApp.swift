import SwiftUI



@main

struct rebuApp: App {



    @StateObject var orderStore = OrderStore()



    var body: some Scene {

        WindowGroup {

            ContentView()

                .environmentObject(orderStore)

        }

    }

}


