import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettings()
                .tabItem { Label("Contas", systemImage: "person.crop.circle") }
            ShortcutSettings()
                .tabItem { Label("Atalho", systemImage: "keyboard") }
        }
        .padding(12)
        .frame(width: 620, height: 520)
    }
}

private struct AccountSettings: View {
    @EnvironmentObject private var store: CadenceStore
    @State private var accounts: [CadenceAccount] = []
    @State private var pendingRemoval: CadenceAccount?
    @State private var validationMessage: String?
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Contas Google")
                        .font(.title2.weight(.semibold))
                    Text("Escolha quais contas abastecem Calendar e Tasks.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Adicionar", action: addAccount)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($accounts) { $account in
                        accountEditor(account: $account)
                    }
                }
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            HStack {
                Button("Cancelar") { closeWindow() }
                Spacer()
                Button("Salvar") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear {
            guard !didLoad else { return }
            accounts = store.configuredAccounts
            didLoad = true
        }
        .confirmationDialog(
            "Remover conta?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { account in
            Button("Remover \(account.label)", role: .destructive) {
                accounts.removeAll { $0.id == account.id }
                pendingRemoval = nil
            }
        } message: { account in
            Text(
                "O token de \(account.label) será removido deste Mac. As credenciais OAuth compartilhadas serão mantidas."
            )
        }
    }

    private func accountEditor(account: Binding<CadenceAccount>) -> some View {
        let value = account.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Nome", text: account.label)
                    .textFieldStyle(.roundedBorder)
                connectionStatus(for: value)
                Button(role: .destructive) {
                    pendingRemoval = value
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 14) {
                Toggle("Calendar", isOn: account.calendar)
                Toggle("Tasks", isOn: account.tasks)
                Spacer()
                Button(store.connectingAccountID == value.id ? "Conectando..." : "Conectar") {
                    connect(value.id)
                }
                .disabled(store.connectingAccountID != nil || (!value.calendar && !value.tasks))
            }
            .toggleStyle(.switch)

            HStack(spacing: 8) {
                TextField("OAuth credentials JSON", text: account.credentialsPath)
                    .textFieldStyle(.roundedBorder)
                Button("Escolher") { chooseCredentials(for: value.id) }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func connectionStatus(for account: CadenceAccount) -> some View {
        if store.connectingAccountID == account.id {
            ProgressView()
                .controlSize(.small)
        } else if store.isConnected(account) {
            Label("Conectada", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label("Não conectada", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addAccount() {
        let id = "account-\(UUID().uuidString.prefix(8).lowercased())"
        let credentialsPath = accounts.first?.credentialsPath ?? "~/.config/cadence/credentials.json"
        accounts.append(
            CadenceAccount(
                id: id,
                label: "Nova conta",
                credentialsPath: credentialsPath,
                tokenPath: "~/.cache/cadence/\(id)-token.json",
                calendar: true,
                tasks: false
            )
        )
    }

    private func chooseCredentials(for accountID: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let index = accounts.firstIndex(where: { $0.id == accountID })
        else { return }
        accounts[index].credentialsPath = url.path
    }

    private func save() {
        guard validate() else { return }
        if store.saveAccounts(accounts) { closeWindow() }
    }

    private func connect(_ accountID: String) {
        guard validate() else { return }
        guard store.saveAccounts(accounts, synchronize: false) else { return }
        store.connect(accountID: accountID)
    }

    private func validate() -> Bool {
        guard !accounts.isEmpty else {
            validationMessage = "Adicione ao menos uma conta."
            return false
        }
        guard accounts.contains(where: { $0.calendar || $0.tasks }) else {
            validationMessage = "Ative Calendar ou Tasks em ao menos uma conta."
            return false
        }
        guard accounts.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            validationMessage = "Todas as contas precisam de um nome."
            return false
        }
        validationMessage = nil
        return true
    }

    private func closeWindow() {
        NSApp.keyWindow?.close()
    }
}
