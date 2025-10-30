import SwiftUI
import PhotosUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isEditingName = false
    @State private var tempDisplayName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Bubbly background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                BubblyProfileBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Avatar Section
                        VStack(spacing: 16) {
                            ZStack {
                                if let avatarURL = viewModel.avatarURL, let url = URL(string: avatarURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 120, height: 120)
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
                                    .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 120, height: 120)
                                        .overlay(
                                            Text(viewModel.displayName.prefix(1).uppercased())
                                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
                                }

                                // Camera button overlay
                                PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 16))
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
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                                }
                                .offset(x: 40, y: 40)
                            }

                            Text("✨ Tap to change")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)

                        // Name Section
                        VStack(spacing: 12) {
                            if isEditingName {
                                VStack(spacing: 12) {
                                    TextField("Display Name", text: $tempDisplayName)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .multilineTextAlignment(.center)
                                        .padding()
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                    HStack(spacing: 12) {
                                        Button {
                                            isEditingName = false
                                            tempDisplayName = viewModel.displayName
                                        } label: {
                                            Text("Cancel")
                                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .background(.ultraThinMaterial)
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }

                                        Button {
                                            viewModel.displayName = tempDisplayName
                                            Task {
                                                await viewModel.updateDisplayName()
                                                isEditingName = false
                                            }
                                        } label: {
                                            Text("Save")
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .background(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(red: 0.98, green: 0.29, blue: 0.55),
                                                            Color(red: 0.58, green: 0.41, blue: 0.87)
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3), radius: 12, x: 0, y: 6)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            } else {
                                Button {
                                    tempDisplayName = viewModel.displayName
                                    isEditingName = true
                                } label: {
                                    HStack {
                                        Text(viewModel.displayName.isEmpty ? "Set your name" : viewModel.displayName)
                                            .font(.system(size: 24, weight: .bold, design: .rounded))
                                            .foregroundColor(.primary)

                                        Image(systemName: "pencil.circle.fill")
                                            .font(.system(size: 20))
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
                            }
                        }

                        // Groups Section
                        if !viewModel.userGroups.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("👥 Your Groups")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal)

                                VStack(spacing: 12) {
                                    ForEach(viewModel.userGroups) { group in
                                        GroupCard(group: group) {
                                            viewModel.groupToLeave = group
                                            viewModel.showingLeaveGroupConfirmation = true
                                        }
                                    }
                                }
                            }
                        }

                        // Action Buttons Section
                        VStack(spacing: 12) {
                            // Sign Out Button
                            Button {
                                Task {
                                    await authViewModel.signOut()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Sign Out")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
                            }

                            // Delete Account Button
                            Button {
                                viewModel.showingDeleteAccountConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Delete Account")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 6)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)

                        // Error Message
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.red)
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 100) // Space for floating tab bar
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading...")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            .alert("Leave Group", isPresented: $viewModel.showingLeaveGroupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Leave", role: .destructive) {
                    if let group = viewModel.groupToLeave {
                        Task {
                            await viewModel.leaveGroup(group)
                        }
                    }
                }
            } message: {
                if let group = viewModel.groupToLeave {
                    Text("Are you sure you want to leave \"\(group.name)\"? You'll need a new invite to rejoin.")
                }
            }
            .alert("Delete Account", isPresented: $viewModel.showingDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Forever", role: .destructive) {
                    Task {
                        let success = await viewModel.deleteAccount()
                        if success {
                            await authViewModel.signOut()
                        }
                    }
                }
            } message: {
                Text("⚠️ This action cannot be undone!\n\nDeleting your account will:\n• Remove you from all groups\n• Delete all your data\n• Sign you out permanently")
            }
            .task {
                await viewModel.loadUserProfile()
            }
            .onChange(of: viewModel.selectedPhotoItem) { _, _ in
                Task {
                    await viewModel.uploadAvatar()
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct GroupCard: View {
    let group: ProfileViewModel.GroupMembership
    let onLeave: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                if let role = group.role {
                    Text(role == "owner" ? "👑 Owner" : "✨ Member")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if group.role != "owner" {
                Button(action: onLeave) {
                    Text("Leave")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

struct BubblyProfileBackground: View {
    var body: some View {
        ZStack {
            // Large pink bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.15),
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 200
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: -100, y: -250)
                .blur(radius: 40)

            // Purple bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.15),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 200
                    )
                )
                .frame(width: 250, height: 250)
                .offset(x: 120, y: 100)
                .blur(radius: 40)

            // Blue bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.12),
                            Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.03)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 150
                    )
                )
                .frame(width: 200, height: 200)
                .offset(x: -80, y: 400)
                .blur(radius: 35)

            // Small decorative bubbles
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 60, height: 60)
                .offset(x: 140, y: -180)
                .blur(radius: 10)

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 40, height: 40)
                .offset(x: -130, y: 50)
                .blur(radius: 8)
        }
    }
}
