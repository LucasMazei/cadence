import AppKit
import SwiftUI

enum CadenceSection: String, CaseIterable, Identifiable {
    case agenda = "Agenda"
    case tasks = "Tasks"
    case calendar = "Calendário"

    var id: Self { self }
}

struct ContentView: View {
    let openSettings: () -> Void
    @EnvironmentObject private var store: CadenceStore
    @State private var section: CadenceSection = .agenda
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $section) {
                ForEach(CadenceSection.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if section != .calendar {
                TextField("Buscar…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            Group {
                switch section {
                case .agenda: AgendaView(search: search)
                case .tasks: TasksView(search: search)
                case .calendar: MonthCalendar()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 420, height: 540)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Cadence").font(.headline)
                if let event = store.nextEvent, let date = event.parsedStartDate {
                    Text("Próximo: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                store.sync()
            } label: {
                Image(systemName: store.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(store.isSyncing ? .degrees(180) : .zero)
            }
            .buttonStyle(.borderless)
            .disabled(store.isSyncing)
            .help("Sincronizar")
            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Configurações")
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .lineLimit(1)
                    .foregroundStyle(.red)
            } else if let updated = store.lastUpdated {
                Text("Atualizado \(updated.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
