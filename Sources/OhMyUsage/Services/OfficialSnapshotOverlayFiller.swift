import OhMyUsageDomain
import Foundation

/// Doc §8.4 (Codex/Claude Web overlay): the OAuth/API snapshot is the primary
/// source of truth. Cookie-based Web data is strictly supplementary — a primary
/// snapshot that already carries complete quota fields skips the overlay
/// entirely, and when the overlay does run, its values only fill slots the
/// primary left empty. Overlay data can never overwrite successful primary
/// quota values.
enum OfficialSnapshotOverlayFiller {
    /// A primary snapshot is quota-complete when both the short (session) and
    /// the long (weekly) window exist with a reset time. Reviews, credits and
    /// other optional metadata do not gate completeness.
    static func isQuotaComplete(_ snapshot: UsageSnapshot) -> Bool {
        guard !snapshot.quotaWindows.isEmpty else { return false }
        return hasCompleteWindow(in: snapshot.quotaWindows, kind: .session)
            && hasCompleteWindow(in: snapshot.quotaWindows, kind: .weekly)
    }

    private static func hasCompleteWindow(
        in windows: [UsageQuotaWindow],
        kind: UsageQuotaKind
    ) -> Bool {
        windows.contains { $0.kind == kind && $0.resetAt != nil }
    }

    /// Merges overlay values into the primary snapshot slot by slot:
    /// - quota windows missing from the primary are appended;
    /// - a missing reset time on an existing window is adopted from the overlay;
    /// - extras/rawMeta keys absent from the primary are added;
    /// - account label and note are used only when the primary has none.
    /// Primary usage percentages, statuses and remaining values always win.
    static func fill(
        primary: UsageSnapshot,
        overlay: UsageSnapshot,
        sourceLabel: String
    ) -> UsageSnapshot {
        var merged = primary
        merged.sourceLabel = sourceLabel
        merged.accountLabel = primary.accountLabel ?? overlay.accountLabel

        var windows = merged.quotaWindows
        var indexByID: [String: Int] = [:]
        for (index, window) in windows.enumerated() where indexByID[window.id] == nil {
            indexByID[window.id] = index
        }
        for overlayWindow in overlay.quotaWindows {
            if let index = indexByID[overlayWindow.id] {
                if windows[index].resetAt == nil {
                    windows[index].resetAt = overlayWindow.resetAt
                }
            } else {
                indexByID[overlayWindow.id] = windows.count
                windows.append(overlayWindow)
            }
        }
        merged.quotaWindows = windows

        for (key, value) in overlay.extras where merged.extras[key] == nil {
            merged.extras[key] = value
        }
        for (key, value) in overlay.rawMeta where merged.rawMeta[key] == nil {
            merged.rawMeta[key] = value
        }
        if merged.note.isEmpty {
            merged.note = overlay.note
        }
        return merged
    }
}
