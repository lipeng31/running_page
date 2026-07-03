import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("RunningPage Sync")
                    .font(.largeTitle.bold())
                Text("Sync Apple Watch workout routes to your running_page repository.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Sync")
        }
    }
}
