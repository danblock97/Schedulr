import SwiftUI
import PhotosUI

struct OnboardingFlowView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch viewModel.step {
                case .avatar:
                    AvatarStep(viewModel: viewModel)
                case .name:
                    NameStep(viewModel: viewModel)
                case .group:
                    GroupStep(viewModel: viewModel)
                case .done:
                    DoneStep(onFinish: { viewModel.onFinished?() })
                }
            }
            .padding()
            .navigationTitle("Welcome ✨")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.step != .avatar {
                        Button("Back") { viewModel.back() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(viewModel.step == .done ? "Finish" : "Next") {
                        Task { await viewModel.next() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

private struct AvatarStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var pickerItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Add a cute avatar (optional)")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let data = viewModel.pickedImageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .shadow(radius: 8)
            } else {
                ZStack {
                    Circle().fill(.gray.opacity(0.15)).frame(width: 120, height: 120)
                    Text("🫧")
                        .font(.system(size: 42))
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose Photo", systemImage: "photo.fill.on.rectangle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.pink.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run { viewModel.pickedImageData = data }
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
            Text("Pick a display name")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            TextField("e.g. BubbleBuddy", text: $viewModel.displayName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .focused($isFocused)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isFocused = true } }
            if viewModel.isSavingName { ProgressView("Saving…") }
            if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red).font(.footnote).multilineTextAlignment(.center) }
        }
    }
}

private struct GroupStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var body: some View {
        VStack(spacing: 18) {
            Text("Groups (optional)")
                .font(.title3.weight(.semibold))
            Picker("Mode", selection: $viewModel.groupMode) {
                Text("Skip").tag(OnboardingViewModel.GroupMode.skip)
                Text("Create").tag(OnboardingViewModel.GroupMode.create)
                Text("Join").tag(OnboardingViewModel.GroupMode.join)
            }.pickerStyle(.segmented)

            switch viewModel.groupMode {
            case .skip:
                Text("You can always manage groups later.")
                    .foregroundStyle(.secondary)
            case .create:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group name")
                        .font(.subheadline.weight(.medium))
                    TextField("e.g. Fun Schedulers", text: $viewModel.groupName)
                        .textFieldStyle(.roundedBorder)
                }
            case .join:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste the invite URL or code")
                        .font(.subheadline.weight(.medium))
                    TextField("https://… or invite-code", text: $viewModel.joinInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }

            if viewModel.isHandlingGroup { ProgressView("Saving…") }
            if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red).font(.footnote).multilineTextAlignment(.center) }
        }
    }
}

private struct DoneStep: View {
    var onFinish: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text("All set! 🎉")
                .font(.title2.weight(.bold))
            Text("You can change your profile anytime in settings.")
                .foregroundStyle(.secondary)
            Button("Go to app", action: onFinish)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    OnboardingFlowView(viewModel: OnboardingViewModel(onFinished: {}))
}

