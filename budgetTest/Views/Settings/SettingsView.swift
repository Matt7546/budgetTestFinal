import SwiftUI

struct SettingsView: View {

    var body: some View {

        NavigationStack {

            List {

                Section("Account") {
                    Label("Profile", systemImage: "person")
                    Label("Notifications", systemImage: "bell")
                }

                Section("Connections") {
                    Label("Plaid Accounts", systemImage: "building.columns")
                }

                Section("App") {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("Profile")
        }
    }
}
