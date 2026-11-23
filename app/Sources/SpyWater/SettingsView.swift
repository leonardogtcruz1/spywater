import SwiftUI

private final class SettingsUIState: ObservableObject {
    @Published var statuslineInstalled = false
    @Published var agyHooksInstalled = false
}

struct SettingsView: View {
    @EnvironmentObject var store: SessionStore

    @AppStorage("holdSeconds") private var holdSeconds: Int = 120
    @AppStorage("terminalApp") private var terminalApp: String = "terminal"
    @AppStorage("notifyYourTurn") private var notifyYourTurn: Bool = false
    @AppStorage("autolaunch") private var autolaunch: Bool = true
    @AppStorage("agyInterceptCommands") private var agyInterceptCommands: Bool = false

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

                Picker("Terminal para retomar (Claude)", selection: $terminalApp) {
                    Text("Terminal").tag("terminal")
                    Text("iTerm").tag("iterm")
                }

                Toggle("Notificar quando uma sessão terminar", isOn: $notifyYourTurn)

                Toggle("Abrir o SpyWater automaticamente quando iniciar", isOn: $autolaunch)
                    .onChange(of: autolaunch) { _, newValue in
                        store.setAutolaunchFile(enabled: newValue)
                    }
            }

            Section("Antigravity / Gemini") {
                LabeledContent("Hooks do Antigravity") {
                    HStack(spacing: 8) {
                        Text(ui.agyHooksInstalled ? "Instalados" : "Não instalados")
                            .foregroundStyle(ui.agyHooksInstalled ? Theme.emerald : Theme.amber)
                        Button("Verificar") {
                            let ok = SessionStore.checkAgyHooksInstalled()
                            ui.agyHooksInstalled = ok
                            store.agyHooksInstalled = ok
                        }
                        .controlSize(.small)
                    }
                }

                if !ui.agyHooksInstalled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Execute no terminal para conectar eventos do Antigravity:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("./scripts/install-agy-hooks.sh")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Toggle("Interceptar comandos (run_command) do Antigravity para aprovar no SpyWater", isOn: $agyInterceptCommands)
            }

            Section("Status e Integrações (Claude Code)") {
                LabeledContent("Servidor local") {
                    if let err = store.serverError {
                        Text(err)
                            .foregroundStyle(.red)
                    } else {
                        Text("Rodando em 127.0.0.1:\(store.server.port)")
                            .foregroundStyle(Theme.emerald)
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
        .frame(width: 520, height: 430)
        .preferredColorScheme(.dark)
        .onAppear {
            let sl = SessionStore.checkStatuslineInstalled()
            let agy = SessionStore.checkAgyHooksInstalled()
            ui.statuslineInstalled = sl
            ui.agyHooksInstalled = agy
            store.statuslineInstalled = sl
            store.agyHooksInstalled = agy
        }
    }
}
