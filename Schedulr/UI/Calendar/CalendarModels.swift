import Foundation

struct DisplayEvent: Identifiable, Equatable {
    let base: CalendarEventWithUser
    let sharedCount: Int
    var id: UUID { base.id }
}


