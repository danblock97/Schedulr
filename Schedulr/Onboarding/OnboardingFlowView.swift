import SwiftUI
import PhotosUI
import EventKit

struct OnboardingFlowView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var previousStep: OnboardingViewModel.Step = .avatar

    var body: some View {
        NavigationStack {
            ZStack {
                BubblyBackground()
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    OnboardingHeader(step: viewModel.step)

                    // Animated stage transitions without boxy containers
                    ZStack {
                        let forward = viewModel.step.rawValue >= previousStep.rawValue
                        let insertion: Edge = forward ? .trailing : .leading
                        let removal: Edge = forward ? .leading : .trailing

                        if viewModel.step == .avatar {
                            AvatarStep(viewModel: viewModel)
                                .transition(.asymmetric(
                                    insertion: .move(edge: insertion).combined(with: .opacity),
                                    removal: .move(edge: removal).combined(with: .opacity)
                                ))
                        }
                        if viewModel.step == .name {
                            NameStep(viewModel: viewModel)
                                .transition(.asymmetric(
                                    insertion: .move(edge: insertion).combined(with: .opacity),
                                    removal: .move(edge: removal).combined(with: .opacity)
                                ))
                        }
                        if viewModel.step == .group {
                            GroupStep(viewModel: viewModel)
                                .transition(.asymmetric(
                                    insertion: .move(edge: insertion).combined(with: .opacity),
                                    removal: .move(edge: removal).combined(with: .opacity)
                                ))
                        }
                        if viewModel.step == .calendar {
                            CalendarStep(viewModel: viewModel)
                                .transition(.asymmetric(
                                    insertion: .move(edge: insertion).combined(with: .opacity),
                                    removal: .move(edge: removal).combined(with: .opacity)
                                ))
                        }
                        if viewModel.step == .done {
                            DoneStep(onFinish: { viewModel.onFinished?() })
                                .transition(.asymmetric(
                                    insertion: .move(edge: insertion).combined(with: .opacity),
                                    removal: .move(edge: removal).combined(with: .opacity)
                                ))
                        }
                    }
                    .frame(maxWidth: 640)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.step)
                }
                .padding()
            }
            .navigationTitle("Welcome ✨")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.step != .avatar {
                        Button {
                            viewModel.back()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.next() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.step == .done ? "Finish" : "Next")
                                .font(.system(size: 16, weight: .semibold))
                            if viewModel.step != .done {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(
                        (viewModel.step == .name && viewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || (viewModel.step == .avatar && viewModel.isUploadingAvatar)
                    )
                    .opacity(
                        (viewModel.step == .name && viewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || (viewModel.step == .avatar && viewModel.isUploadingAvatar) ? 0.5 : 1.0
                    )
                    .keyboardShortcut(.defaultAction)
                }
            }
            .onChange(of: viewModel.step) { oldValue, _ in
                previousStep = oldValue
            }
        }
    }
}

private struct AvatarStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var pickerItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(spacing: 20) {
            if let data = viewModel.pickedImageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 132, height: 132)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.29, blue: 0.55),
                                        Color(red: 0.58, green: 0.41, blue: 0.87)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 4
                            )
                    )
                    .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3), radius: 12, x: 0, y: 6)
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.08),
                                    Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 132, height: 132)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3),
                                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    Image(systemName: "person.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.on.rectangle")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Upload Photo")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55),
                            Color(red: 0.58, green: 0.41, blue: 0.87)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run { viewModel.pickedImageData = data }
                        // Auto-upload and advance when a photo is chosen
                        await viewModel.next()
                    }
                }
            }

            if viewModel.isUploadingAvatar { ProgressView("Uploading…") }
            if let url = viewModel.avatarPublicURL { Text("Uploaded to \(url.absoluteString)").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red).font(.footnote).multilineTextAlignment(.center) }
        }
    }
}

private struct NameStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Display name")
                        .font(.subheadline.weight(.semibold))
                    Text("*")
                        .foregroundStyle(.red)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityLabel("Required")
                }
                TextField("Alex Morgan", text: $viewModel.displayName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($isFocused)
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isFocused = true } }
            if viewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Display name is required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if viewModel.isSavingName { ProgressView("Saving…") }
            if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red).font(.footnote).multilineTextAlignment(.center) }
        }
    }
}

private struct GroupStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var body: some View {
        VStack(spacing: 18) {
            // Create by default
            VStack(alignment: .leading, spacing: 8) {
                Text("Create a group")
                    .font(.subheadline.weight(.semibold))
                TextField("e.g. Weekend Warriors", text: $viewModel.groupName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.groupName) { _, val in
                        // If user types a name, prefer create mode
                        if !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.groupMode = .create
                        }
                    }
            }

            // OR separator with lines
            HStack(spacing: 12) {
                Rectangle().fill(.quaternary).frame(height: 1).frame(maxWidth: .infinity)
                Text("or")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Rectangle().fill(.quaternary).frame(height: 1).frame(maxWidth: .infinity)
            }

            // Join via link/code
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    // Vertical accent line
                    Rectangle().fill(.quaternary).frame(width: 1, height: 24)
                    Text("Already have a link? Paste it here to join")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                TextField("https://… or invite-code", text: $viewModel.joinInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: viewModel.joinInput) { _, val in
                        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.groupMode = trimmed.isEmpty ? .create : .join
                    }
            }

            Divider()

            // Subtle skip link (not a button)
            Button(action: {
                viewModel.groupMode = .skip
                Task { await viewModel.next() }
            }) {
                Text("Set up later")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)

            if viewModel.isHandlingGroup {
                ProgressView(viewModel.groupMode == .create ? "Creating…" : (viewModel.groupMode == .join ? "Joining…" : "Saving…"))
            }
            if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red).font(.footnote).multilineTextAlignment(.center) }
        }
    }
}

private struct CalendarStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var calendarSync: CalendarSyncManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bring your schedule")
                    .font(.subheadline.weight(.semibold))
                Text("Let Schedulr show your upcoming events so the group can see when you're busy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: Binding(
                get: { viewModel.wantsCalendarSync },
                set: { newValue in
                    viewModel.wantsCalendarSync = newValue
                    if !newValue {
                        calendarSync.disableSync()
                    }
                }
            )) {
                Text("Sync my personal calendars")
                    .font(.body.weight(.medium))
            }
            .toggleStyle(.switch)

            Group {
                switch calendarSync.authorizationStatus {
                case .notDetermined:
                    Text("We'll ask for permission on the next step.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .authorized:
                    if calendarSync.syncEnabled && !calendarSync.upcomingEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming (next 2 weeks)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(Array(calendarSync.upcomingEvents.prefix(3))) { event in
                                CalendarPreviewRow(event: event)
                            }
                            if calendarSync.upcomingEvents.count > 3 {
                                Text("…and \(calendarSync.upcomingEvents.count - 3) more")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if viewModel.wantsCalendarSync {
                        Text("We'll pull in your next couple of weeks once calendar access is granted.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .denied, .restricted:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Calendar access is turned off.")
                            .font(.footnote.weight(.semibold))
                        Text("You can enable it later in Settings > Privacy > Calendars.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    EmptyView()
                }
            }

            if calendarSync.isRequestingAccess {
                ProgressView("Requesting access…")
            } else if calendarSync.isRefreshing {
                ProgressView("Syncing events…")
            }

            if let error = viewModel.errorMessage, viewModel.step == .calendar {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalendarPreviewRow: View {
    let event: CalendarSyncManager.SyncedEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color(for: event))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "Busy" : event.title)
                    .font(.subheadline.weight(.semibold))
                Text(formattedDateRange(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
    }

    private func formattedDateRange(for event: CalendarSyncManager.SyncedEvent) -> String {
        if event.isAllDay {
            return "All day • \(event.calendarTitle)"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let sameDay = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)

        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .none

        if sameDay {
            return "\(dayFormatter.string(from: event.startDate)) • \(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
        } else {
            return "\(dayFormatter.string(from: event.startDate)) \(formatter.string(from: event.startDate)) → \(dayFormatter.string(from: event.endDate)) \(formatter.string(from: event.endDate))"
        }
    }

    private func color(for event: CalendarSyncManager.SyncedEvent) -> Color {
        Color(
            red: event.calendarColor.red,
            green: event.calendarColor.green,
            blue: event.calendarColor.blue,
            opacity: event.calendarColor.alpha
        )
    }
}
private struct DoneStep: View {
    var onFinish: () -> Void
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("All set! 🎉")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
            
            Text("You can change your profile anytime in settings.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Soft upgrade prompt for free users
            if !subscriptionManager.isPro {
                OnboardingProPromo(onUpgrade: { showPaywall = true }, onSkip: onFinish)
            }
            
            Button(action: onFinish) {
                HStack(spacing: 10) {
                    Text("Go to app")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55),
                            Color(red: 0.58, green: 0.41, blue: 0.87)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 20)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

private struct OnboardingProPromo: View {
    let onUpgrade: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55),
                            Color(red: 0.58, green: 0.41, blue: 0.87)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)
            
            Text("Unlock Pro")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            VStack(spacing: 8) {
                ProFeatureRow(text: "AI scheduling assistant")
                ProFeatureRow(text: "5 groups instead of 1")
                ProFeatureRow(text: "10 members per group")
            }
            .padding(.vertical, 8)
            
            HStack(spacing: 12) {
                Button(action: onUpgrade) {
                    Text("Buy Pro")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                }
                
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
        }
        .padding(24)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
}

private struct ProFeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.59, green: 0.85, blue: 0.34))
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let manager = CalendarSyncManager()
    return OnboardingFlowView(viewModel: OnboardingViewModel(calendarManager: manager, onFinished: {}))
        .environmentObject(manager)
}

// MARK: - Bubbly styling helpers (UI-only)

private struct BubblyBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            // Tasteful color: subtle radial accents
            RadialGradient(
                colors: [Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 280
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()
        }
    }
}

// Wizard header with progress and step title
private struct OnboardingHeader: View {
    let step: OnboardingViewModel.Step
    private var count: Int { OnboardingViewModel.Step.allCases.count }
    private var index: Int { step.rawValue }
    private var progress: CGFloat { CGFloat(index + 1) / CGFloat(count) }
    private var title: String {
        switch step {
        case .avatar: return "Make it yours"
        case .name: return "A name to go by"
        case .group: return "Find your crew"
        case .calendar: return "Sync your calendar"
        case .done: return "Ready to roll"
        }
    }
    private var subtitle: String {
        switch step {
        case .avatar: return "Add a profile photo—put a face to your plans."
        case .name: return "How should we address you across Schedulr?"
        case .group: return "Create or join a group now, or skip and do it later."
        case .calendar: return "Pull in your personal calendars so everyone can see when you're busy."
        case .done: return "Nice! You can tweak these anytime in settings."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                AppLogoMark()
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Text("Step \(index + 1) of \(count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
            ProgressBar(progress: progress)
            Text(subtitle)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: 640)
        .padding(.top, 8)
    }
}

private struct ProgressBar: View {
    let progress: CGFloat // 0...1
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = max(16, proxy.size.height)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: h/2, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: h/2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                Color(red: 0.58, green: 0.41, blue: 0.87)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(16, w * min(max(progress, 0), 1)))
                    .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
        .frame(height: 14)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
    }
}

// Small app logo mark (with fallback)
private struct AppLogoMark: View {
    var body: some View {
        if UIImage(named: "schedulr-logo") != nil {
            Image("schedulr-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel("Schedulr Logo")
        } else if UIImage(named: "schedulr-logo-any") != nil {
            Image("schedulr-logo-any")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel("Schedulr Logo")
        } else {
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
    }
}
