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
                case .agenda: eventList
                case .tasks: taskList
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

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredEvents) { event in
                    EventRow(event: event) { store.open(event) }
                }
                if filteredEvents.isEmpty { emptyState("Nenhum evento encontrado", icon: "calendar.badge.checkmark") }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedTasks) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            TaskRow(
                                task: task,
                                onToggle: { store.setTaskCompleted(task, completed: !task.isCompleted) },
                                onOpen: { store.open(task) }
                            )
                        }
                    } header: {
                        TaskDayHeader(title: group.title, isOverdue: group.isOverdue)
                    }
                }
                if groupedTasks.isEmpty { emptyState("Nenhuma task encontrada", icon: "checkmark.circle") }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
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

    private var filteredEvents: [CadenceEvent] {
        let future = store.events
            .filter { ($0.parsedStartDate ?? .distantPast) >= Calendar.current.startOfDay(for: Date()) }
            .sorted { ($0.parsedStartDate ?? .distantFuture) < ($1.parsedStartDate ?? .distantFuture) }
        guard !search.isEmpty else { return future }
        return future.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var filteredTasks: [CadenceTask] {
        let sorted = store.tasks.sorted {
            ($0.parsedDueDate ?? .distantFuture) < ($1.parsedDueDate ?? .distantFuture)
        }
        guard !search.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || ($0.list?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    private var groupedTasks: [TaskDayGroup] {
        let calendar = Calendar.current
        let dated = Dictionary(grouping: filteredTasks.filter { $0.parsedDueDate != nil }) {
            calendar.startOfDay(for: $0.parsedDueDate!)
        }

        var groups = dated.keys.sorted().map { date in
            TaskDayGroup(
                id: DateFormatter.googleTaskDay.string(from: date),
                title: taskGroupTitle(for: date),
                isOverdue: date < calendar.startOfDay(for: Date()),
                tasks: dated[date] ?? []
            )
        }

        let withoutDate = filteredTasks.filter { $0.parsedDueDate == nil }
        if !withoutDate.isEmpty {
            groups.append(
                TaskDayGroup(
                    id: "no-date",
                    title: "Sem data",
                    isOverdue: false,
                    tasks: withoutDate
                ))
        }
        return groups
    }

    private func taskGroupTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hoje" }
        if calendar.isDateInTomorrow(date) { return "Amanhã" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        ContentUnavailableView(title, systemImage: icon)
            .frame(height: 250)
    }
}

private struct TaskDayGroup: Identifiable {
    let id: String
    let title: String
    let isOverdue: Bool
    let tasks: [CadenceTask]
}

private struct TaskDayHeader: View {
    let title: String
    let isOverdue: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if isOverdue {
                Text("Atrasadas")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.12), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background(.regularMaterial)
    }
}

private struct EventRow: View {
    let event: CadenceEvent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Text(event.parsedStartDate?.formatted(.dateTime.day()) ?? "–")
                        .font(.title3.bold())
                    Text(event.parsedStartDate?.formatted(.dateTime.month(.abbreviated)) ?? "")
                        .font(.caption2)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.body.weight(.medium)).lineLimit(2)
                    if let account = event.account {
                        Text(account)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                    if let date = event.parsedStartDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let description = event.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(11)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct TaskRow: View {
    let task: CadenceTask
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .strikethrough(task.isCompleted)
                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if let list = task.list { Text(list) }
                            if let due = task.parsedDueDate {
                                Text("·")
                                Text(due.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button(action: onOpen) {
                Image(systemName: "arrow.up.right").font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }
}
