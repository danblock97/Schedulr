import SwiftUI

struct AppIssueBanner: View {
    let alert: AppIssueAlert
    let onMoreInfo: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if isCompactLayout {
                compactBanner
            } else {
                regularBanner
            }
        }
    }

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var compactBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)

            Text(alert.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            ctaButton(compact: true)

            dismissButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(bannerBackground)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var regularBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(alert.message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)
                dismissButton
            }

            ctaButton(compact: false)
        }
        .padding(10)
        .background(bannerBackground)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss issue banner")
    }

    private var bannerBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func ctaButton(compact: Bool) -> some View {
        Button {
            onMoreInfo()
        } label: {
            HStack(spacing: compact ? 4 : 6) {
                Text("More Info")
                    .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "info.circle")
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
            }
            .foregroundStyle(accentColor)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 6)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows full issue details")
    }

    private var iconName: String {
        switch alert.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "bolt.horizontal.circle.fill"
        }
    }

    private var accentColor: Color {
        switch alert.severity {
        case .info:
            return .blue
        case .warning:
            return Color(red: 0.95, green: 0.55, blue: 0.10)
        case .critical:
            return .red
        }
    }

    private var borderColor: Color {
        accentColor.opacity(colorScheme == .dark ? 0.4 : 0.22)
    }
}
