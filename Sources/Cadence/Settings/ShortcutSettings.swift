import AppKit
import SwiftUI

struct ShortcutSettings: View {
    @ObservedObject private var manager = GlobalShortcut.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Abrir o Cadence").font(.headline)
            Text("Use o atalho em qualquer app para abrir o painel da barra de menus.")
                .foregroundStyle(.secondary)
            HStack {
                Button(manager.isRecording ? "Cancelar gravação" : manager.shortcut?.label ?? "Gravar atalho") {
                    if manager.isRecording {
                        manager.stopRecording()
                    } else {
                        manager.startRecording()
                    }
                }
                if manager.shortcut != nil {
                    Button("Remover") { manager.remove() }
                }
            }
            if manager.isRecording {
                Text("Pressione a combinação desejada ou Esc para cancelar.")
                    .font(.callout)
            }
            if let message = manager.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { manager.stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            manager.stopRecording()
        }
    }
}
