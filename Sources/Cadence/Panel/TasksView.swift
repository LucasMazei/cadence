import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: CadenceStore
    let search: String

    var body: some View {
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
                if groupedTasks.isEmpty {
                    ContentUnavailableView("Nenhuma task encontrada", systemImage: "checkmark.circle")
                        .frame(height: 250)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
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
