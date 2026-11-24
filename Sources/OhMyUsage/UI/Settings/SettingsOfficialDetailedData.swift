import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    struct OfficialDetailedDataRow: Identifiable {
        var id: String
        var key: String
        var value: String
    }

    struct OfficialDetailedDataGroup: Identifiable {
        var id: String
        var title: String
        var rows: [OfficialDetailedDataRow]
    }

    func shouldShowOfficialDetailedDataCard(for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official else { return false }
        switch provider.type {
        case .codex, .claude, .gemini, .antigravity, .kimi:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    func officialDetailedDataSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        let groups = officialDetailedDataGroups(provider: provider, snapshot: snapshot, error: error)

        officialAccountMonitorCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    providerIcon(for: provider, size: 12)
                    Text(viewModel.localizedText("详细数据", "Detailed Data"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                    Spacer(minLength: 8)
                }
                .frame(height: 24)

                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        dividerLine
                            .padding(.vertical, 10)
                    } else {
                        Spacer().frame(height: 8)
                    }
                    officialDetailedDataGroupView(group)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func officialDetailedDataGroupView(_ group: OfficialDetailedDataGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            if group.rows.isEmpty {
                Text("--")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
            } else {
                ForEach(group.rows) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.key)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                            .frame(width: 136, alignment: .leading)

                        Text(row.value)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsBodyColor)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func officialDetailedDataGroups(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> [OfficialDetailedDataGroup] {
        let conciseRows = officialDetailedConciseRows(provider: provider, snapshot: snapshot)
        return [
            OfficialDetailedDataGroup(
                id: "concise",
                title: viewModel.localizedText("关键信息", "Key Info"),
                rows: conciseRows
            )
        ]
    }

    private func officialDetailedConciseRows(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> [OfficialDetailedDataRow] {
        let noteValue = detailedValueOrPlaceholder(snapshot?.note)
        let usageSummary = officialDetailedUsageSummaryValue(provider: provider, snapshot: snapshot)

        return [
            OfficialDetailedDataRow(
                id: "concise.note",
                key: "note",
                value: noteValue
            ),
            OfficialDetailedDataRow(
                id: "concise.usage",
                key: viewModel.localizedText("用量", "Usage"),
                value: usageSummary
            )
        ]
    }

    private func officialDetailedUsageSummaryValue(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> String {
        let scope = localUsageTrendScope(for: provider)
        let accountOptions = localUsageTrendAccountOptions(for: provider, snapshot: snapshot)
        let selectedAccountKey = localUsageTrendSelectedAccountKey(
            providerID: provider.id,
            options: accountOptions
        )
        let identityContext = localUsageTrendIdentityContext(
            for: provider,
            snapshot: snapshot,
            selectedAccountKey: selectedAccountKey,
            accountOptions: accountOptions
        )
        let identityCacheKey = localUsageTrendEffectiveIdentityCacheKey(
            scope: scope,
            identityCacheKey: identityContext.cacheIdentity
        )
        let query = LocalUsageHistoryQuery(
            providerType: provider.type,
            providerID: provider.id,
            scope: scope,
            identityKey: identityCacheKey
        )

        let historyState = viewModel.localUsageHistoryState(for: query)
        let strictSummary = historyState.summary
        let summary = localUsageTrendDisplaySummary(
            provider: provider,
            scope: scope,
            identityCacheKey: identityCacheKey,
            strictSummary: strictSummary
        ) ?? strictSummary
        if let summary {
            return localUsageTrendSummaryText(summary)
        }

        if historyState.isLoading {
            return viewModel.localizedText("读取趋势中...", "Loading trend...")
        }

        return viewModel.localizedText("暂无趋势数据", "No trend data")
    }

    private func officialDetailedDataGroupsFull(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> [OfficialDetailedDataGroup] {
        var groups: [OfficialDetailedDataGroup] = [
            OfficialDetailedDataGroup(
                id: "base",
                title: viewModel.localizedText("基础状态", "Base Status"),
                rows: officialDetailedBaseRows(snapshot: snapshot, error: error)
            ),
            OfficialDetailedDataGroup(
                id: "main-quota",
                title: viewModel.localizedText("主额度", "Primary Quota"),
                rows: officialDetailedMainQuotaRows(snapshot: snapshot)
            )
        ]

        groups.append(
            OfficialDetailedDataGroup(
                id: "quota-windows",
                title: viewModel.localizedText("quotaWindows 明细", "quotaWindows Details"),
                rows: officialDetailedQuotaWindowRows(snapshot: snapshot)
            )
        )
        groups.append(
            OfficialDetailedDataGroup(
                id: "extras",
                title: "extras",
                rows: officialDetailedDictionaryRows(
                    snapshot?.extras ?? [:],
                    prefix: "extras",
                    maskSensitive: true
                )
            )
        )
        groups.append(
            OfficialDetailedDataGroup(
                id: "rawMeta",
                title: "rawMeta",
                rows: officialDetailedDictionaryRows(
                    snapshot?.rawMeta ?? [:],
                    prefix: "rawMeta",
                    maskSensitive: true
                )
            )
        )

        return groups
    }

    private func officialDetailedBaseRows(
        snapshot: UsageSnapshot?,
        error: String?
    ) -> [OfficialDetailedDataRow] {
        var rows: [OfficialDetailedDataRow] = []

        if let snapshot {
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.source",
                    key: "source",
                    value: snapshot.source
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.status",
                    key: "status",
                    value: snapshot.status.rawValue
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.fetchHealth",
                    key: "fetchHealth",
                    value: snapshot.fetchHealth.rawValue
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.freshness",
                    key: "valueFreshness",
                    value: snapshot.valueFreshness.rawValue
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.updatedAt",
                    key: "updatedAt",
                    value: isoDateText(snapshot.updatedAt)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.sourceLabel",
                    key: "sourceLabel",
                    value: detailedValueOrPlaceholder(snapshot.sourceLabel)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.accountLabel",
                    key: "accountLabel",
                    value: detailedValueOrPlaceholder(snapshot.accountLabel)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.authSourceLabel",
                    key: "authSourceLabel",
                    value: detailedValueOrPlaceholder(snapshot.authSourceLabel)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.diagnosticCode",
                    key: "diagnosticCode",
                    value: detailedValueOrPlaceholder(snapshot.diagnosticCode)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.note",
                    key: "note",
                    value: detailedValueOrPlaceholder(snapshot.note)
                )
            )
        } else {
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.snapshot",
                    key: "snapshot",
                    value: viewModel.localizedText("暂无快照", "No snapshot")
                )
            )
        }

        if let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.error",
                    key: "error",
                    value: error
                )
            )
        }

        return rows
    }

    private func officialDetailedMainQuotaRows(snapshot: UsageSnapshot?) -> [OfficialDetailedDataRow] {
        guard let snapshot else {
            return [
                OfficialDetailedDataRow(
                    id: "main-quota.snapshot",
                    key: "quota",
                    value: viewModel.localizedText("暂无快照", "No snapshot")
                )
            ]
        }
        return [
            OfficialDetailedDataRow(
                id: "main-quota.remaining",
                key: "remaining",
                value: snapshot.remaining.map { String(format: "%.2f", $0) } ?? "-"
            ),
            OfficialDetailedDataRow(
                id: "main-quota.used",
                key: "used",
                value: snapshot.used.map { String(format: "%.2f", $0) } ?? "-"
            ),
            OfficialDetailedDataRow(
                id: "main-quota.limit",
                key: "limit",
                value: snapshot.limit.map { String(format: "%.2f", $0) } ?? "-"
            ),
            OfficialDetailedDataRow(
                id: "main-quota.unit",
                key: "unit",
                value: detailedValueOrPlaceholder(snapshot.unit)
            )
        ]
    }

    private func officialDetailedQuotaWindowRows(snapshot: UsageSnapshot?) -> [OfficialDetailedDataRow] {
        guard let snapshot, !snapshot.quotaWindows.isEmpty else {
            return [
                OfficialDetailedDataRow(
                    id: "quota-windows.none",
                    key: "windows",
                    value: viewModel.localizedText("暂无数据", "No data")
                )
            ]
        }

        return snapshot.quotaWindows.enumerated().map { index, window in
            let remainingText = String(format: "%.2f", window.remainingPercent)
            let usedText = String(format: "%.2f", window.usedPercent)
            let resetAtText = window.resetAt.map(isoDateText) ?? "-"
            let observedAtText = window.observedAt.map(isoDateText) ?? "-"
            let identityText = window.windowIdentity ?? "-"
            return OfficialDetailedDataRow(
                id: "quota-windows.\(window.id).\(index)",
                key: "window[\(index)]",
                value: "id=\(window.id) | title=\(window.title) | kind=\(window.kind.rawValue) | remainingPercent=\(remainingText) | usedPercent=\(usedText) | resetAt=\(resetAtText) | resetSource=\(window.resetSource.rawValue) | confidence=\(window.confidence.rawValue) | observedAt=\(observedAtText) | windowIdentity=\(identityText)"
            )
        }
    }

    private func officialDetailedDictionaryRows(
        _ values: [String: String],
        prefix: String,
        maskSensitive: Bool
    ) -> [OfficialDetailedDataRow] {
        guard !values.isEmpty else {
            return [
                OfficialDetailedDataRow(
                    id: "\(prefix).none",
                    key: prefix,
                    value: viewModel.localizedText("暂无数据", "No data")
                )
            ]
        }

        return values.keys.sorted().map { key in
            let rawValue = values[key] ?? ""
            let displayValue = maskSensitive
                ? maskedDetailedValue(forKey: key, rawValue: rawValue)
                : detailedValueOrPlaceholder(rawValue)
            return OfficialDetailedDataRow(
                id: "\(prefix).\(key)",
                key: key,
                value: displayValue
            )
        }
    }

    private func isoDateText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func detailedValueOrPlaceholder(_ value: String?) -> String {
        guard let value else { return "-" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private func maskedDetailedValue(forKey key: String, rawValue: String) -> String {
        let normalized = detailedValueOrPlaceholder(rawValue)
        guard normalized != "-" else { return normalized }
        guard isSensitiveDetailedKey(key) else { return normalized }
        return maskedSensitiveText(normalized)
    }

    private func isSensitiveDetailedKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        let fragments = [
            "token",
            "cookie",
            "auth",
            "secret",
            "key",
            "password",
            "session",
            "bearer",
            "jwt",
            "refresh",
            "access"
        ]
        return fragments.contains { lower.contains($0) }
    }

    private func maskedSensitiveText(_ text: String) -> String {
        guard text.count > 6 else {
            return String(repeating: "*", count: max(1, text.count))
        }
        let prefixCount = min(3, text.count)
        let suffixCount = min(3, max(0, text.count - prefixCount))
        let prefix = String(text.prefix(prefixCount))
        let suffix = String(text.suffix(suffixCount))
        let maskCount = max(4, text.count - prefixCount - suffixCount)
        return prefix + String(repeating: "*", count: maskCount) + suffix
    }
}
