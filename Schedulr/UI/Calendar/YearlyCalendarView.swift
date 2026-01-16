import SwiftUI

struct YearlyCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var displayedYear: Date
    let events: [DisplayEvent]
    var onMonthSelected: ((Date) -> Void)?
    
    private let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let weekSpacing: CGFloat = 2
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<12, id: \.self) { monthIndex in
                    monthCell(monthIndex: monthIndex)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }
    
    private func monthCell(monthIndex: Int) -> some View {
        let monthDate = Calendar.current.date(bySetting: .month, value: monthIndex + 1, of: displayedYear) ?? displayedYear
        let isSelectedMonth = Calendar.current.isDate(monthDate, equalTo: selectedDate, toGranularity: .month)
        let isCurrentMonth = Calendar.current.isDate(monthDate, equalTo: Date(), toGranularity: .month)
        
        return VStack(alignment: .leading, spacing: 8) {
            // Month name
            Text(months[monthIndex])
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelectedMonth || isCurrentMonth ? .red : .primary)
            
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { index, day in
                    Text(day)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            let days = daysInMonth(for: monthDate)
            let weeks = weeksInMonth(days)
            VStack(spacing: weekSpacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, weekDays in
                    weekRow(weekDays: weekDays, monthDate: monthDate, monthIndex: monthIndex)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let onMonthSelected = onMonthSelected {
                // Get first day of the month
                let firstDay = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: monthDate)) ?? monthDate
                onMonthSelected(firstDay)
            }
        }
    }
    
    private func dayCell(day: Date, monthDate: Date, monthIndex: Int) -> some View {
        let isCurrentMonth = Calendar.current.isDate(day, equalTo: monthDate, toGranularity: .month)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDateInToday(day)
        let dayNumber = Calendar.current.component(.day, from: day)
        let dayEvents = eventsForDay(day)
        let eventColor = !dayEvents.isEmpty ? (dayEvents.first?.base.effectiveColor != nil ? Color(
            red: dayEvents.first!.base.effectiveColor!.red,
            green: dayEvents.first!.base.effectiveColor!.green,
            blue: dayEvents.first!.base.effectiveColor!.blue,
            opacity: dayEvents.first!.base.effectiveColor!.alpha
        ) : Color(red: 0.58, green: 0.41, blue: 0.87)) : Color(red: 0.58, green: 0.41, blue: 0.87)
        
        return ZStack {
            if isSelected {
                Circle()
                    .fill(Color.red)
                    .frame(width: 20, height: 20)
            } else if isToday {
                Circle()
                    .stroke(Color.red, lineWidth: 1)
                    .frame(width: 20, height: 20)
            }
            
            Text("\(dayNumber)")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(isSelected ? .white : (isCurrentMonth ? .primary : .secondary))
        }
        .frame(width: 20, height: 20)
        .overlay(
            Group {
                if !dayEvents.isEmpty {
                    Circle()
                        .fill(eventColor)
                        .frame(width: 3, height: 3)
                        .offset(x: 7, y: 7)
                }
            }
        )
        .onTapGesture {
            withAnimation {
                selectedDate = day
            }
        }
    }
    
    private func weekRow(weekDays: [Date], monthDate: Date, monthIndex: Int) -> some View {
        let segments = layoutMultiDaySegments(for: weekDays)
        
        return ZStack(alignment: .topLeading) {
            HStack(spacing: weekSpacing) {
                ForEach(weekDays, id: \.self) { day in
                    dayCell(day: day, monthDate: monthDate, monthIndex: monthIndex)
                        .frame(maxWidth: .infinity)
                }
            }
            
            multiDayBarsOverlay(segments: segments)
        }
    }
    
    private func layoutMultiDaySegments(for weekDays: [Date]) -> [YearWeekSpan] {
        let sortedSegments = multiDaySegments(for: events, weekDays: weekDays).sorted { a, b in
            if a.startIndex == b.startIndex {
                return a.endIndex > b.endIndex
            }
            return a.startIndex < b.startIndex
        }
        
        var rowEndIndexes: [Int] = []
        var result: [YearWeekSpan] = []
        
        for segment in sortedSegments {
            var assignedRow: Int?
            for (row, endIndex) in rowEndIndexes.enumerated() {
                if segment.startIndex > endIndex {
                    assignedRow = row
                    rowEndIndexes[row] = segment.endIndex
                    break
                }
            }
            if assignedRow == nil {
                rowEndIndexes.append(segment.endIndex)
                assignedRow = rowEndIndexes.count - 1
            }
            
            result.append(YearWeekSpan(segment: segment, row: assignedRow ?? 0))
        }
        
        return result
    }
    
    private func multiDayBarsOverlay(segments: [YearWeekSpan]) -> some View {
        GeometryReader { geometry in
            let totalSpacing = weekSpacing * 6
            let cellWidth = (geometry.size.width - totalSpacing) / 7
            let barHeight: CGFloat = 3
            let barSpacing: CGFloat = 1
            let barBaseline: CGFloat = 16
            
            if cellWidth >= 12 {
                ForEach(segments) { span in
                    let spanDays = span.segment.endIndex - span.segment.startIndex + 1
                    let rawWidth = (CGFloat(spanDays) * cellWidth) + (CGFloat(spanDays - 1) * weekSpacing)
                    let barWidth = max(rawWidth - 2, 2)
                    let xOffset = (CGFloat(span.segment.startIndex) * (cellWidth + weekSpacing)) + 1
                    let yOffset = barBaseline - (CGFloat(span.row) * (barHeight + barSpacing))
                    let cornerRadius = barHeight / 2
                    let event = span.segment.event
                    
                    UnevenRoundedRectangle(
                        topLeadingRadius: span.segment.continuesFromPrevious ? 1 : cornerRadius,
                        bottomLeadingRadius: span.segment.continuesFromPrevious ? 1 : cornerRadius,
                        bottomTrailingRadius: span.segment.continuesToNext ? 1 : cornerRadius,
                        topTrailingRadius: span.segment.continuesToNext ? 1 : cornerRadius
                    )
                    .fill(eventColor(event).opacity(0.9))
                    .frame(width: barWidth, height: barHeight)
                    .offset(x: xOffset, y: yOffset)
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func daysInMonth(for monthDate: Date) -> [Date] {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: monthDate)) ?? monthDate
        let range = Calendar.current.range(of: .day, in: .month, for: start) ?? 1..<31
        var days: [Date] = range.compactMap { day -> Date? in
            Calendar.current.date(byAdding: .day, value: day - 1, to: start)
        }
        
        // Prepend previous month days to align first weekday (Sunday = 1)
        let firstWeekday = Calendar.current.component(.weekday, from: start)
        let prefix = firstWeekday - 1
        if prefix > 0 {
            for i in 1...prefix {
                if let d = Calendar.current.date(byAdding: .day, value: -i, to: start) {
                    days.insert(d, at: 0)
                }
            }
        }
        
        // Append next month days to fill rows
        while days.count % 7 != 0 {
            if let lastDay = days.last {
                days.append(Calendar.current.date(byAdding: .day, value: 1, to: lastDay)!)
            } else {
                break
            }
        }
        
        return days
    }
    
    private func weeksInMonth(_ days: [Date]) -> [[Date]] {
        guard !days.isEmpty else { return [] }
        return stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<min(index + 7, days.count)])
        }
    }
    
    private func eventsForDay(_ day: Date) -> [DisplayEvent] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        
        return events.filter { event in
            if event.base.is_all_day {
                // For all-day events, check if the day falls within the inclusive date range
                let eventStart = Calendar.current.startOfDay(for: event.base.start_date)
                let eventEnd = Calendar.current.startOfDay(for: event.base.end_date)
                // Day must be >= event start AND <= event end (inclusive)
                return dayStart >= eventStart && dayStart <= eventEnd
            } else {
                // For timed events, use overlap logic with actual event times
                let eventStart = event.base.start_date
                let eventEnd = event.base.end_date
                
                // Event overlaps with the day if:
                // - Event starts before the day ends AND
                // - Event ends after the day starts
                return eventStart < dayEnd && eventEnd > dayStart
            }
        }
    }
    
    private func eventColor(_ event: DisplayEvent) -> Color {
        if let color = event.base.effectiveColor {
            return Color(
                red: color.red,
                green: color.green,
                blue: color.blue,
                opacity: color.alpha
            )
        }
        return Color(red: 0.58, green: 0.41, blue: 0.87)
    }
}

private struct YearWeekSpan: Identifiable {
    let segment: MultiDaySpanSegment
    let row: Int
    
    var id: String {
        "\(segment.id)-row-\(row)"
    }
}

