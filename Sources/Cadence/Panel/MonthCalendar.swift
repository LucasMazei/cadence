import SwiftUI

struct MonthCalendar: View {
    @Environment(\.calendar) private var calendar
    @State private var monthOffset = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    static func leadingSpacerIDs(for monthStart: Date, in calendar: Calendar) -> Range<Int> {
        let count = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        // The grid also uses day numbers as IDs when switching months.
        return (-count)..<0
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            if let currentMonth = calendar.dateInterval(of: .month, for: timeline.date)?.start,
                let month = calendar.date(byAdding: .month, value: monthOffset, to: currentMonth),
                let days = calendar.range(of: .day, in: .month, for: month)
            {
                VStack(spacing: 18) {
                    HStack {
                        Text(month, format: .dateTime.month(.wide).year())
                            .font(.headline)
                        Spacer()
                        Button {
                            monthOffset -= 1
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Mês anterior")
                        Button("Hoje") { monthOffset = 0 }
                        Button {
                            monthOffset += 1
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .accessibilityLabel("Próximo mês")
                    }
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(0..<7) { index in
                            let weekday = (calendar.firstWeekday - 1 + index) % 7
                            Text(calendar.shortStandaloneWeekdaySymbols[weekday])
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday])
                        }
                        ForEach(Self.leadingSpacerIDs(for: month, in: calendar), id: \.self) { _ in
                            Color.clear.frame(height: 32).accessibilityHidden(true)
                        }
                        ForEach(days, id: \.self) { day in
                            let isToday =
                                calendar.isDate(month, equalTo: timeline.date, toGranularity: .month)
                                && day == calendar.component(.day, from: timeline.date)
                            Text(day, format: .number)
                                .monospacedDigit()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(isToday ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
                                .background { if isToday { Circle().fill(Color.accentColor) } }
                                .accessibilityLabel(isToday ? "Hoje, dia \(day)" : "Dia \(day)")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }
        }
    }
}
