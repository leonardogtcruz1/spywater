import SwiftUI

private final class SettingsUIState: ObservableObject {
    @Published var statuslineInstalled = false
}

struct SettingsView: View {
    @EnvironmentObject var store: SessionStore

    @AppStorage("holdSeconds") private var holdSeconds: Int = 120
    @AppStorage("terminalApp") private var terminalApp: String = "terminal"
    @AppStorage("notifyYourTurn") private var notifyYourTurn: Bool = false
    @AppStorage("autolaunch") private var autolaunch: Bool = true

    @StateObject private var ui = SettingsUIState()

    var body: some View {
        Form {
            Section("Comportamento") {
                Picker("Segurar pedidos no painel por", selection: $holdSeconds) {
                    Text("30 s").tag(30)
                    Text("2 min").tag(120)
                    Text("10 min").tag(600)
                    Text("Sempre").tag(0)
                }

                Picker("Terminal para retomar", selection: $terminalApp) {
                    Text("Terminal").tag("terminal")
                    Text("iTerm").tag("iterm")
                }

                Toggle("Notificar quando uma sessão terminar", isOn: $notifyYourTurn)

                Toggle("Abrir o SpyWater automaticamente quando o Claude iniciar", isOn: $autolaunch)
                    .onChange(of: autolaunch) { _, newValue in
                        store.setAutolaunchFile(enabled: newValue)
                    }
            }

            Section("Status e Integrações") {
                LabeledContent("Servidor local") {
                    if let err = store.serverError {
                        Text(err)
                            .foregroundStyle(.red)
                    } else {
                        Text("Rodando em 127.0.0.1:\(store.server.port)")
                            .foregroundStyle(.green)
                    }
                }

                LabeledContent("Status line (uso do plano)") {
                    HStack(spacing: 8) {
                        Text(ui.statuslineInstalled ? "Instalada" : "Não instalada")
                            .foregroundStyle(ui.statuslineInstalled ? Theme.emerald : Theme.amber)
                        Button("Verificar") {
                            let ok = SessionStore.checkStatuslineInstalled()
                            ui.statuslineInstalled = ok
                            store.statuslineInstalled = ok
                        }
                        .controlSize(.small)
                    }
                }

                if !ui.statuslineInstalled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Execute no terminal para ativar o monitoramento de limites 5h/semanal:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("./scripts/install-statusline.sh")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 340)
        .preferredColorScheme(.dark)
        .onAppear {
            let ok = SessionStore.checkStatuslineInstalled()
            ui.statuslineInstalled = ok
            store.statuslineInstalled = ok
        }
    }
}
