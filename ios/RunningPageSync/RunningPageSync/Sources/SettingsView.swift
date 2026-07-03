import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: GitHubSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Repository") {
                TextField("Owner", text: $settingsStore.settings.owner)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Repository", text: $settingsStore.settings.repository)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Branch", text: $settingsStore.settings.branch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Workflow file", text: $settingsStore.settings.workflowFileName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Token") {
                SecureField("Fine-grained PAT", text: $settingsStore.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Token needs Contents read/write and Actions read/write for this repository.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    settingsStore.reload()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    settingsStore.save()
                    dismiss()
                }
            }
        }
    }
}
