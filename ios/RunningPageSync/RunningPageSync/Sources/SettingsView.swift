import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: GitHubSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(settingsStore.isReady ? "Ready" : "Incomplete")
                        .foregroundStyle(settingsStore.isReady ? .green : .orange)
                } label: {
                    Label("Connection", systemImage: "network")
                }
            }

            Section {
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
            } header: {
                Label("Repository", systemImage: "shippingbox")
            }

            Section {
                SecureField("Fine-grained token", text: $settingsStore.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
            } header: {
                Label("Access Token", systemImage: "key")
            }
        }
        .navigationTitle("GitHub Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    settingsStore.reload()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    settingsStore.save()
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .disabled(!settingsStore.isReady)
            }
        }
    }
}
