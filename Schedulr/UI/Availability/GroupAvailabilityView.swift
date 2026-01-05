import SwiftUI

/// Visual heat map showing when group members are free
/// Part of the "share when you're free" casual availability feature
struct GroupAvailabilityView: View {
    @StateObject private var viewModel: GroupAvailabilityViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showingDetail = false
    @State private var selectedDate: Date?
    @State private var selectedBlock: GroupAvailabilityViewModel.TimeBlock?
    
    init(groupId: UUID, members: [DashboardViewModel.MemberSummary]) {
        _viewModel = StateObject(wrappedValue: GroupAvailabilityViewModel(
            groupId: groupId,
            members: members
        ))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero section
                    heroSection
                    
                    // "Everyone's free" highlight
                    if let highlight = viewModel.topHighlight {
                        EveryoneFreeHighlightBanner(
                            highlight: highlight,
                            memberCount: highlight.memberCount
                        ) {
                            // Could navigate to create event
                        }
                        .padding(.horizontal)
                    }
                    
                    // Heat map
                    heatMapSection
                    
                    // Legend
                    legendSection
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 10)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("When's good?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(themeManager.primaryColor)
                            .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                            .animation(
                                viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                value: viewModel.isLoading
                            )
                    }
                    .disabled(viewModel.isLoading)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                await viewModel.loadAvailability()
            }
            .overlay {
                if showingDetail, let date = selectedDate, let block = selectedBlock {
                    detailOverlay(date: date, block: block)
                }
            }
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(themeManager.primaryColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(themeManager.gradient)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find the best time")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    
                    Text("See when everyone's free to hang")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(themeManager.primaryColor.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Heat Map Section
    
    private var heatMapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(themeManager.primaryColor)
                
                Text("This week")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            
            if let error = viewModel.errorMessage {
                errorBanner(message: error)
            } else if viewModel.availabilitySummary.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                VStack(spacing: 8) {
                    // Day headers
                    DayHeaderRow(dates: viewModel.displayDates)
                    
                    // Time block rows
                    ForEach(GroupAvailabilityViewModel.TimeBlock.allCases) { block in
                        TimeBlockRow(
                            block: block,
                            dates: viewModel.displayDates,
                            viewModel: viewModel
                        ) { date, tappedBlock in
                            selectedDate = date
                            selectedBlock = tappedBlock
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingDetail = true
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Legend Section
    
    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the colors mean")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                legendItem(color: themeManager.primaryColor, label: "Everyone free")
                legendItem(color: .green.opacity(0.7), label: "Most free")
                legendItem(color: .yellow.opacity(0.8), label: "Some free")
                legendItem(color: .orange.opacity(0.7), label: "Few free")
                legendItem(
                    color: colorScheme == .dark ? .gray.opacity(0.3) : .gray.opacity(0.2),
                    label: "Busy"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal)
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 20)
            
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(themeManager.primaryColor.opacity(0.1))
                    .frame(width: 70, height: 70)
                
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(themeManager.gradient)
            }
            
            VStack(spacing: 6) {
                Text("No availability yet")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                
                Text("Members need to share when they're free")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }
    
    // MARK: - Detail Overlay
    
    private func detailOverlay(date: Date, block: GroupAvailabilityViewModel.TimeBlock) -> some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingDetail = false
                    }
                }
            
            // Detail popover
            let summary = viewModel.getBlockSummary(for: date, block: block)
            let freeMemberNames = viewModel.freeMemberNames(for: summary.freeMemberIds)
            
            AvailabilityDetailPopover(
                date: date,
                block: block,
                freeMemberNames: freeMemberNames,
                totalMembers: summary.totalMembers
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingDetail = false
                }
            }
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Compact Availability Preview

/// A compact inline view for showing availability on the dashboard
struct AvailabilityPreviewCard: View {
    let groupId: UUID
    let members: [DashboardViewModel.MemberSummary]
    let onTap: () -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    @State private var topHighlight: EveryoneFreeHighlight?
    @State private var isLoading = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(themeManager.primaryColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(themeManager.gradient)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let highlight = topHighlight {
                        Text("Everyone's free!")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text(highlight.friendlyDescription)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("See when everyone's free")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Find a time that works for all")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        topHighlight != nil ?
                        AnyShapeStyle(LinearGradient(
                            colors: [themeManager.primaryColor.opacity(0.25), themeManager.secondaryColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )) :
                            AnyShapeStyle(Color.primary.opacity(0.04)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .task {
            await loadHighlight()
        }
    }
    
    private func loadHighlight() async {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: 7, to: startDate) else { return }
        
        do {
            let highlights = try await AvailabilityService.shared.findEveryoneFreeHighlights(
                groupId: groupId,
                startDate: startDate,
                endDate: endDate
            )
            topHighlight = highlights.first
        } catch {
            print("[AvailabilityPreviewCard] Failed to load highlights: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    GroupAvailabilityView(
        groupId: UUID(),
        members: [
            DashboardViewModel.MemberSummary(
                id: UUID(),
                displayName: "Alice",
                role: "owner",
                avatarURL: nil,
                joinedAt: nil
            ),
            DashboardViewModel.MemberSummary(
                id: UUID(),
                displayName: "Bob",
                role: "member",
                avatarURL: nil,
                joinedAt: nil
            )
        ]
    )
    .environmentObject(ThemeManager.shared)
}

