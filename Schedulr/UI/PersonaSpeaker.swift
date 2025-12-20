import SwiftUI
import Combine

struct PersonaPhrase: Identifiable {
    let id = UUID()
    let text: String
    let context: PhraseContext
    
    enum PhraseContext {
        case morning, afternoon, evening, generic, motivation
    }
}

class PersonaSpeaker: ObservableObject {
    @Published var currentPhrase: String = ""
    @Published var isSpeaking: Bool = false
    
    // SFW Jokes / Light-hearted comments
    private var allPhrases: [PersonaPhrase] = [
        PersonaPhrase(text: "Why did the calendar go on a diet? It had too many dates!", context: .generic),
        PersonaPhrase(text: "I'm not lazy, I'm just on energy saving mode.", context: .afternoon),
        PersonaPhrase(text: "Parallel lines have so much in common. It’s a shame they’ll never meet.", context: .generic),
        PersonaPhrase(text: "My battery is at 100%, how about you?", context: .morning),
        PersonaPhrase(text: "Planning is just guessing with a calendar.", context: .motivation),
        PersonaPhrase(text: "I told my computer I needed a break, and now it won't stop sending me Kit-Kats.", context: .generic)
    ]
    
    private var upcomingEvents: [CalendarEventWithUser] = []
    private var isPro: Bool = false
    private var userName: String?
    private var timer: AnyCancellable?
    
    // Static to persist across view recreations so we don't spam the user
    private static var hasSpokenInitialGreeting: Bool = false
    
    private var lastPhrases: [String] = [] // History to prevent repetition
    
    init() {
        startSpeakingCycle()
    }
    
    func updateData(events: [CalendarEventWithUser], isPro: Bool, userName: String?) {
        self.upcomingEvents = events
        self.isPro = isPro
        self.userName = userName
        
        // If we have data and haven't greeted yet THIS SESSION, do it now
        if !Self.hasSpokenInitialGreeting && !upcomingEvents.isEmpty && userName != nil {
            speakInitialGreeting()
        }
    }
    
    func startSpeakingCycle() {
        // Initial delay before starting the cycle logic
        // Note: The actual initial greeting happens in updateData when data arrives
        
        // Cycle every 45 seconds - much slower to avoid "bombarding"
        timer = Timer.publish(every: 45, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.speakRandomPhrase()
            }
    }
    
    private func speakInitialGreeting() {
        guard !Self.hasSpokenInitialGreeting else { return }
        Self.hasSpokenInitialGreeting = true
        
        let name = userName ?? "friend"
        var greeting = ""
        
        // 1. Initial Greeting (No "Pro User" text, just welcome)
        greeting = "Welcome back, \(name)! "
        
        // 2. Event Summary
        if !upcomingEvents.isEmpty {
            let count = upcomingEvents.count
            let firstEvent = upcomingEvents[0]
            
            // Format date relative to today
            let calendar = Calendar.current
            let start = firstEvent.start_date
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeStr = formatter.string(from: start)
            
            let dayStr: String
            if calendar.isDateInToday(start) {
                dayStr = "today"
            } else if calendar.isDateInTomorrow(start) {
                dayStr = "tomorrow"
            } else {
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEEE" // Full day name
                dayStr = "on \(dayFormatter.string(from: start))"
            }
            
            if count == 1 {
                greeting += "You have one event coming up: \(firstEvent.title), \(dayStr) at \(timeStr)."
            } else {
                greeting += "You have \(count) upcoming events. First up is \(firstEvent.title), \(dayStr) at \(timeStr)."
            }
        } else {
            greeting += "Your schedule is clear for now."
        }
        
        speak(greeting, duration: 8.0) // Show longer for the summary
    }
    
    func speakRandomPhrase() {
        // If we haven't done the initial greeting yet (maybe data was late), try that first
        if !Self.hasSpokenInitialGreeting && !upcomingEvents.isEmpty {
            speakInitialGreeting()
            return
        }
        
        var candidates: [String] = []
        let name = userName ?? "friend"
        
        // 1. Data-driven phrases (~60% chance if available)
        if let nextEvent = upcomingEvents.first, Bool.random() {
            let calendar = Calendar.current
            let start = nextEvent.start_date
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeStr = formatter.string(from: start)
            
            let dayStr: String
            if calendar.isDateInToday(start) {
                dayStr = "today"
            } else if calendar.isDateInTomorrow(start) {
                dayStr = "tomorrow"
            } else {
                 let dF = DateFormatter(); dF.dateFormat = "MMM d"; dayStr = dF.string(from: start)
            }
            
            candidates.append("Don't forget: \(nextEvent.title) is \(dayStr) at \(timeStr).")
            candidates.append("Next up: \(nextEvent.title) (\(dayStr) at \(timeStr)).")
            candidates.append("You have \(nextEvent.title) coming up \(dayStr).")
        }
        
        // 2. Jokes / Fun phrases (Fallback)
        if candidates.isEmpty || Bool.random() {
            // Pick a random joke that isn't in recent history
            let joke = allPhrases.randomElement()?.text ?? "Hello!"
            candidates.append(joke)
        }
        
        // Filter out recently spoken phrases
        let availableCandidates = candidates.filter { !lastPhrases.contains($0) }
        
        if let newPhrase = availableCandidates.randomElement() ?? candidates.first {
            speak(newPhrase)
        }
    }
    
    private func speak(_ text: String, duration: TimeInterval = 6.0) {
        // Prevent strictly identical consecutive repetition
        if currentPhrase == text && isSpeaking { return }
        
        addToHistory(text)
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            self.currentPhrase = text
            self.isSpeaking = true
        }
        
        // Hide after 'duration'
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeOut(duration: 0.5)) {
                self.isSpeaking = false
            }
        }
    }
    
    private func addToHistory(_ text: String) {
        lastPhrases.append(text)
        if lastPhrases.count > 5 {
            lastPhrases.removeFirst()
        }
    }
}
