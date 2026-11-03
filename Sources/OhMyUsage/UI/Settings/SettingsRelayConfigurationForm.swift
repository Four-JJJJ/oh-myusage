import Foundation
import SwiftUI

extension SettingsView {
    func relayCompactConfigRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsConfigRow(title: title) {
            content()
        }
    }

    func relayPillControl(
        selection: String,
        options: [(String, String)],
        width: CGFloat,
        segmentWidths: [String: CGFloat]? = nil,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        settingsConfigSegmentedControl(
            options: options.map { SettingsPillSegmentOption(id: $0.0, title: $0.1) },
            selection: selection,
            width: width,
            segmentWidths: segmentWidths
        ) { newValue in
            onSelect(newValue)
        }
    }

    func relayReadOnlyField(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.80))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .frame(width: thirdPartyConfigControlWidth, height: 24, alignment: .leading)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.15))
            )
    }

    func relayDisplaySiteAddress(_ baseURL: String) -> String {
        guard let components = URLComponents(string: baseURL),
              let scheme = components.scheme,
              let host = components.host else {
            return baseURL
        }
        var output = "\(scheme)://\(host)"
        if let port = components.port {
            output += ":\(port)"
        }
        return output
    }

    func relayCondensedTestStatusText(_ result: RelayDiagnosticResult) -> String {
        if result.success {
            return viewModel.localizedText("链接成功接口正常", "Connection succeeded and endpoint is healthy")
        }
        return result.message
    }
}
