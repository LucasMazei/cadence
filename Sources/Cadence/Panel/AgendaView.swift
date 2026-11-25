import SwiftUI

struct AgendaView: View {
    @EnvironmentObject private var store: CadenceStore
    let search: String

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredEvents) { event in
                    EventRow(event: event) { store.open(event) }
                }
                if filteredEvents.isEmpty {
                    ContentUnavailableView("Nenhum evento encontrado", systemImage: "calendar.badge.checkmark")
                        .frame(height: 250)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var filteredEvents: [CadenceEvent] {
        let future = store.events
            .filter { ($0.parsedStartDate ?? .distantPast) >= Calendar.current.startOfDay(for: Date()) }
            .sorted { ($0.parsedStartDate ?? .distantFuture) < ($1.parsedStartDate ?? .distantFuture) }
        guard !search.isEmpty else { return future }
        return future.filter { $0.title.localizedCaseInsensitiveContains(search) }
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
