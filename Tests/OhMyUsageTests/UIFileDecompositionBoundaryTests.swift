import Foundation
import XCTest

final class UIFileDecompositionBoundaryTests: XCTestCase {
    func testSettingsThresholdRowsStayInThresholdControls() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sharedHelpersURL = rootURL.appendingPathComponent("Sources/OhMyUsage/UI/Settings/SettingsSharedHelpers.swift")
        let thresholdControlsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/UI/Settings/SettingsThresholdControls.swift")
        let sharedHelpers = try String(contentsOf: sharedHelpersURL, encoding: .utf8)
        let sharedHelpersLineCount = sharedHelpers.split(separator: "\n", omittingEmptySubsequences: false).count

        XCTAssertLessThanOrEqual(
            sharedHelpersLineCount,
            460,
            "SettingsSharedHelpers.swift should stay below the threshold/quota split budget"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: thresholdControlsURL.path),
            "Threshold row helpers should live in SettingsThresholdControls.swift"
        )

        guard FileManager.default.fileExists(atPath: thresholdControlsURL.path) else {
            return
        }

        let thresholdControls = try String(contentsOf: thresholdControlsURL, encoding: .utf8)
        for focusedResponsibility in [
            "settingsConfigThresholdRow(",
            "SettingsCompactThresholdSlider",
            "SettingsThresholdValueField"
        ] {
            XCTAssertTrue(
                thresholdControls.contains(focusedResponsibility),
                "SettingsThresholdControls.swift should own \(focusedResponsibility)"
            )
        }

        for sharedResponsibility in [
            "settingsConfigThresholdRow(",
            "SettingsCompactThresholdSlider(",
            "SettingsThresholdValueField("
        ] {
            XCTAssertFalse(
                sharedHelpers.contains(sharedResponsibility),
                "SettingsSharedHelpers.swift should not re-own threshold responsibility \(sharedResponsibility)"
            )
        }
    }

    func testSettingsQuotaHelpersStayInQuotaDisplayHelpers() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sharedHelpersURL = rootURL.appendingPathComponent("Sources/OhMyUsage/UI/Settings/SettingsSharedHelpers.swift")
        let quotaHelpersURL = rootURL.appendingPathComponent("Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift")
        let sharedHelpers = try String(contentsOf: sharedHelpersURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: quotaHelpersURL.path),
            "Quota display helpers should live in SettingsQuotaDisplayHelpers.swift"
        )

        guard FileManager.default.fileExists(atPath: quotaHelpersURL.path) else {
            return
        }

        let quotaHelpers = try String(contentsOf: quotaHelpersURL, encoding: .utf8)
        for focusedResponsibility in [
            "quotaMetricLayout(",
            "codexQuotaMetricView(",
            "codexQuotaMetrics(",
            "codexQuotaValueText("
        ] {
            XCTAssertTrue(
                quotaHelpers.contains(focusedResponsibility),
                "SettingsQuotaDisplayHelpers.swift should own \(focusedResponsibility)"
            )
            XCTAssertFalse(
                sharedHelpers.contains(focusedResponsibility),
                "SettingsSharedHelpers.swift should not re-own quota display responsibility \(focusedResponsibility)"
            )
        }
    }

    func testMenuCardPrimitiveViewsStayOutOfMenuContentView() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let menuContentURL = rootURL.appendingPathComponent("Sources/OhMyUsage/UI/MenuContentView.swift")
        let menuContent = try String(contentsOf: menuContentURL, encoding: .utf8)
        let menuContentLineCount = menuContent.split(separator: "\n", omittingEmptySubsequences: false).count
        let candidatePrimitiveFiles = [
            "Sources/OhMyUsage/UI/MenuModelCardsView.swift",
            "Sources/OhMyUsage/UI/MenuCardPrimitives.swift"
        ]
        let primitiveSources = candidatePrimitiveFiles.compactMap { file -> String? in
            let fileURL = rootURL.appendingPathComponent(file)
            return try? String(contentsOf: fileURL, encoding: .utf8)
        }.joined(separator: "\n")

        XCTAssertLessThanOrEqual(
            menuContentLineCount,
            620,
            "MenuContentView.swift should stay below the card primitive split budget"
        )
        XCTAssertFalse(
            primitiveSources.isEmpty,
            "Menu card primitive subviews should live in MenuModelCardsView.swift or MenuCardPrimitives.swift"
        )

        for primitiveDefinition in [
            "struct PercentageModelCard",
            "struct AmountModelCard",
            "struct ModelCardDivider",
            "struct ModelIconBadge",
            "struct ModelTitleWithPlanType",
            "struct HoverActionButton",
            "struct CardStatus",
            "struct PercentageMetricDisplay"
        ] {
            XCTAssertTrue(
                primitiveSources.contains(primitiveDefinition),
                "MenuModelCardsView.swift or MenuCardPrimitives.swift should own \(primitiveDefinition)"
            )
            XCTAssertFalse(
                menuContent.contains(primitiveDefinition),
                "MenuContentView.swift should not re-own menu card primitive \(primitiveDefinition)"
            )
        }
    }
}
