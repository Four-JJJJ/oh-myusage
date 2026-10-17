import SwiftUI
import OhMyUsagePresentation

struct MenuPermissionGuideView: View {
    let presentation: MenuPermissionGuidePresentation
    let discoveryMessage: String?
    let discoveryIsError: Bool
    let actionProvider: (MenuPermissionGuideRowPresentation.ActionKind?) -> (() -> Void)?

    var body: some View {
        // 首次引导权限卡样式。
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text(presentation.privacyPromise)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(presentation.rows, id: \.kind) { row in
                MenuPermissionGuideRowView(
                    row: row,
                    statusColor: statusColor(for: row.tone),
                    action: actionProvider(row.actionKind)
                )
            }

            if let discoveryMessage, !discoveryMessage.isEmpty {
                Text(discoveryMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(discoveryIsError ? SettingsVisualTokens.Status.discoveryError : SettingsVisualTokens.Status.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SettingsVisualTokens.Menu.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.card, style: .continuous)
                .fill(SettingsVisualTokens.Menu.cardBackground)
        )
    }

    private func statusColor(for tone: MenuPermissionGuideRowPresentation.Tone) -> Color {
        switch tone {
        case .success:
            return SettingsVisualTokens.Status.success
        case .warning:
            return SettingsVisualTokens.Status.warning
        }
    }
}

private struct MenuPermissionGuideRowView: View {
    let row: MenuPermissionGuideRowPresentation
    let statusColor: Color
    let action: (() -> Void)?

    var body: some View {
        // 权限引导卡中的单行项样式（标题、状态胶囊、右侧按钮）。
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(row.statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(statusColor.opacity(0.95))
                        )
                }
                Text(row.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle = row.actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(SettingsVisualTokens.Status.accentBlue)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.panel, style: .continuous)
                .fill(SettingsVisualTokens.Fill.rowHover)
        )
    }
}
