import SwiftUI

struct DayTimelineView: View {
    let events: [CalendarEventWithUser]
    let members: [UUID: (name: String, color: Color)]
    @Binding var date: Date
    let currentUserId: UUID?
    var onTimeRangeSelected: ((Date, Date) -> Void)? = nil

    @State private var isDragging = false
    @State private var dragStartY: CGFloat? = nil
    @State private var dragCurrentY: CGFloat? = nil

    private func isPrivate(_ event: CalendarEventWithUser) -> Bool {
        return event.event_type == "personal" && event.user_id != currentUserId
    }

    private let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            allDayEventsBar
            dayGrid
        }
    }

    @ViewBuilder
    private var allDayEventsBar: some View {
        let allDayEvents = allDayEventsForDate(date)
        if !allDayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("all-day")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: timeColumnWidth - 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(allDayEvents, id: \.id) { event in
                                NavigationLink(destination: EventDetailView(event: event, member: members[event.user_id], currentUserId: currentUserId)) {
                                    HStack(spacing: 4) {
                                        Text(isPrivate(event) ? "Busy" : (event.title.isEmpty ? "Busy" : event.title))
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        if let name = members[event.user_id]?.name {
                                            Text("• \(name)")
                                                .font(.system(size: 10, weight: .regular))
                                                .lineLimit(1)
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(eventColor(event))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 8)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var timeBackground: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(label(for: hour))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: timeColumnWidth, height: hourHeight, alignment: .top)
                        .padding(.top, -8)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle().fill(Color.secondary.opacity(0.1)).frame(height: 1)
                    Spacer().frame(height: hourHeight - 1)
                }
            }
        }
    }

    // MARK: - Day grid with drag support

    private var dayGrid: some View {
        ScrollView {
            dayGridContent
                .frame(height: hourHeight * 24)
                .frame(minHeight: 600)
        }
        .scrollDisabled(isDragging)
    }

    private var dayGridContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                timeBackground
                dragGestureLayer(width: geometry.size.width)
                dragSelectionOverlay(width: geometry.size.width)
                eventsOverlay(in: geometry)
                    .allowsHitTesting(!isDragging)
            }
        }
    }

    // MARK: - Drag gesture layer

    private func dragGestureLayer(width: CGFloat) -> some View {
        let layerWidth = width - timeColumnWidth
        return Color.clear
            .contentShape(Rectangle())
            .frame(width: layerWidth, height: hourHeight * 24)
            .offset(x: timeColumnWidth)
            .gesture(makeDragGesture())
    }

    private func makeDragGesture() -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    break
                case .second(true, let drag):
                    guard let drag = drag else { break }
                    if !isDragging {
                        isDragging = true
                        let y = snapToQuarterHour(drag.startLocation.y)
                        dragStartY = y
                        dragCurrentY = y
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else {
                        dragCurrentY = snapToQuarterHour(drag.location.y)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                defer {
                    isDragging = false
                    dragStartY = nil
                    dragCurrentY = nil
                }
                guard let sY = dragStartY, let cY = dragCurrentY else { return }
                let topY = min(sY, cY)
                let bottomY = max(sY, cY)
                let start = dateFromY(topY)
                let end = dateFromY(bottomY)
                if end.timeIntervalSince(start) >= 15 * 60 {
                    onTimeRangeSelected?(start, end)
                }
            }
    }

    // MARK: - Drag selection overlay

    @ViewBuilder
    private func dragSelectionOverlay(width: CGFloat) -> some View {
        if isDragging, let startY = dragStartY, let currentY = dragCurrentY {
            let topY = min(startY, currentY)
            let bottomY = max(startY, currentY)
            let height = bottomY - topY
            let overlayWidth = width - timeColumnWidth - 8

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
                    .frame(width: overlayWidth, height: max(height, 4))
                    .offset(x: timeColumnWidth + 4, y: topY)

                timeLabel(for: dateFromY(topY))
                    .offset(x: timeColumnWidth + 8, y: topY - 10)

                if abs(bottomY - topY) > 10 {
                    timeLabel(for: dateFromY(bottomY))
                        .offset(x: timeColumnWidth + 8, y: bottomY - 4)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Helpers

    private func snapToQuarterHour(_ y: CGFloat) -> CGFloat {
        let quarterHourHeight = hourHeight / 4.0
        let snapped = (y / quarterHourHeight).rounded() * quarterHourHeight
        return max(0, min(snapped, hourHeight * 24))
    }

    private func dateFromY(_ y: CGFloat) -> Date {
        let totalMinutes = (y / hourHeight) * 60.0
        let snappedMinutes = (totalMinutes / 15.0).rounded() * 15.0
        let clampedMinutes = max(0, min(snappedMinutes, 24 * 60))
        let hour = Int(clampedMinutes) / 60
        let minute = Int(clampedMinutes) % 60
        let dayStart = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) ?? dayStart
    }

    private func timeLabel(for labelDate: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return Text(formatter.string(from: labelDate))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
    }

    // MARK: - Events overlay

    private func eventsOverlay(in geometry: GeometryProxy) -> some View {
        let dayWidth = geometry.size.width - timeColumnWidth
        let dayEvents = eventsForDay(date)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(dayEvents.enumerated()), id: \.element.id) { idx, e in
                let y = CGFloat(minutes(fromStart: e.start_date)) / 60.0 * hourHeight
                let h = CGFloat(max(30, minutesDuration(e))) / 60.0 * hourHeight
                NavigationLink(destination: EventDetailView(event: e, member: members[e.user_id], currentUserId: currentUserId)) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if let emoji = e.category?.emoji {
                                Text(emoji)
                                    .font(.system(size: 11))
                            }
                            Text(isPrivate(e) ? "Busy" : e.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        if let name = members[e.user_id]?.name { Text(name).font(.system(size: 10)) }
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(width: dayWidth - 8, height: max(40, h), alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(eventColor(e).opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(eventColor(e), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .offset(x: timeColumnWidth + 4, y: y + 1)
            }
        }
    }

    private func eventsForDay(_ day: Date) -> [CalendarEventWithUser] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return events.filter {
            !$0.is_all_day && $0.start_date < dayEnd && $0.end_date > dayStart
        }
    }

    private func allDayEventsForDate(_ day: Date) -> [CalendarEventWithUser] {
        events.filter {
            $0.is_all_day && Calendar.current.isDate($0.start_date, inSameDayAs: day)
        }
    }

    private func label(for hour: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "ha"
        let d = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return f.string(from: d).lowercased()
    }

    private func minutes(fromStart d: Date) -> Int {
        let h = Calendar.current.component(.hour, from: d)
        let m = Calendar.current.component(.minute, from: d)
        return h * 60 + m
    }

    private func minutesDuration(_ e: CalendarEventWithUser) -> Int {
        max(30, Int(e.end_date.timeIntervalSince(e.start_date) / 60))
    }

    private func eventColor(_ e: CalendarEventWithUser) -> Color {
        if let color = e.effectiveColor {
            return Color(
                red: color.red,
                green: color.green,
                blue: color.blue,
                opacity: color.alpha
            )
        }
        return members[e.user_id]?.color ?? .blue
    }
}
