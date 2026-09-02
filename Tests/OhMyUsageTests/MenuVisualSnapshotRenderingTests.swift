import AppKit
import OhMyUsageDomain
import SwiftUI
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

/// Phase 4 visual acceptance evidence (doc §10): renders the real menu panel
/// and settings detail views for representative credibility states with
/// SwiftUI `ImageRenderer` and writes PNG files to `/tmp/omu-visual/`.
///
/// Constraints honored here:
/// - No production code is modified; every view is the production view.
/// - Snapshot payloads are placeholder data only (no real credentials).
/// - PNGs are written to /tmp, never into the repository.
///
/// Snapshot filling follows the real app paths:
/// - live states: `providerFactory` stub + `refreshProvider(forceRefresh: true)`
/// - cachedFallback states: seed a temp-directory `PersistedSnapshotCache`
///   file and pass it through the DEBUG `persistedSnapshotCache` init so the
///   cold-start restore path (`restorePersistedSnapshotsFromCache`) runs.
/// - pendingRefresh state: no snapshot at all (never refreshed).
@MainActor
final class MenuVisualSnapshotRenderingTests: XCTestCase {
    private static let outputDirectory = URL(fileURLWithPath: "/tmp/omu-visual")

    // MARK: - Scenario 1: menu panel, live multi-provider (zh-Hans)

    func testRenderMenuLivePanelZh() async throws {
        let viewModel = try await makeLiveMenuViewModel(language: .zhHans, idSuffix: "zh")

        let state = viewModel.menuViewState(now: Date())
        XCTAssertEqual(state.cards.count, 3, "Expected codex group card + relay card + kimi card")
        XCTAssertTrue(
            state.cards.contains { card in
                if case .officialGroup = card { return true } else { return false }
            },
            "Codex official group card must be built from the real slot upsert path"
        )
        for descriptor in viewModel.config.providers where descriptor.enabled {
            XCTAssertEqual(viewModel.snapshots[descriptor.id]?.valueFreshness, .live)
        }

        try renderPNG(
            MenuContentView(viewModel: viewModel, onOpenSettings: nil),
            fileName: "menu-live-zh.png",
            proposedSize: NSSize(width: 340, height: 800),
            fitToNaturalSize: true
        )
    }

    // MARK: - Scenario 2: menu panel, same live state in English

    func testRenderMenuLivePanelEn() async throws {
        let viewModel = try await makeLiveMenuViewModel(language: .en, idSuffix: "en")

        let state = viewModel.menuViewState(now: Date())
        XCTAssertEqual(state.cards.count, 3)

        try renderPNG(
            MenuContentView(viewModel: viewModel, onOpenSettings: nil),
            fileName: "menu-live-en.png",
            proposedSize: NSSize(width: 340, height: 800),
            fitToNaturalSize: true
        )
    }

    // MARK: - Scenario 3: menu panel, auth failure + rate limited

    func testRenderMenuAuthFailedAndRateLimitedPanel() async throws {
        var authRelay = ProviderDescriptor.makeOpenRelay(name: "中转站·认证失效", baseURL: "https://auth-failed-visual.test/v1")
        authRelay.id = "relay-visual-auth-failed"
        authRelay.enabled = true

        var rateRelay = ProviderDescriptor.makeOpenRelay(name: "中转站·限流中", baseURL: "https://rate-limited-visual.test/v1")
        rateRelay.id = "relay-visual-rate-limited"
        rateRelay.enabled = true

        // Cached values are seeded through the real persisted snapshot cache
        // file so the cold-start restore marks them as cachedFallback.
        let cacheDirectory = try makeTemporaryDirectory(named: "menu-auth-failed")
        let cache = makeSnapshotCache(
            directory: cacheDirectory,
            entries: [
                authRelay.id: makeCachedSeedSnapshot(source: authRelay.id, remaining: 45, used: 55, limit: 100),
                rateRelay.id: makeCachedSeedSnapshot(source: rateRelay.id, remaining: 12, used: 88, limit: 100),
            ]
        )

        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [authRelay, rateRelay]),
            appUpdateService: NoopVisualAppUpdateService(),
            providerFactory: StubVisualSnapshotFactory(
                snapshotsByProviderID: [:],
                errorsByProviderID: [
                    authRelay.id: ProviderError.unauthorized,
                    rateRelay.id: ProviderError.rateLimited,
                ]
            ),
            persistedSnapshotCache: cache
        )

        // Init restored the seeded snapshots via the real cache restore path.
        XCTAssertEqual(viewModel.snapshots[authRelay.id]?.valueFreshness, .cachedFallback)
        XCTAssertEqual(viewModel.snapshots[rateRelay.id]?.valueFreshness, .cachedFallback)

        await viewModel.refreshProvider(viewModel.config.providers[0], forceRefresh: true)
        await viewModel.refreshProvider(viewModel.config.providers[1], forceRefresh: true)

        // Auth failure: stale cached values stay on screen under an error chip.
        XCTAssertEqual(viewModel.snapshots[authRelay.id]?.fetchHealth, .authExpired)
        XCTAssertEqual(viewModel.snapshots[authRelay.id]?.valueFreshness, .cachedFallback)
        XCTAssertNotNil(viewModel.errors[authRelay.id])
        // Rate limit: cached values marked with rate-limited fetch health.
        XCTAssertEqual(viewModel.snapshots[rateRelay.id]?.fetchHealth, .rateLimited)
        XCTAssertEqual(viewModel.snapshots[rateRelay.id]?.status, .warning)

        try renderPNG(
            MenuContentView(viewModel: viewModel, onOpenSettings: nil),
            fileName: "menu-auth-failed.png",
            proposedSize: NSSize(width: 340, height: 800),
            fitToNaturalSize: true
        )
    }

    // MARK: - Scenario 4: menu panel, cached fallback + pending + long name

    func testRenderMenuCachedFallbackLongNamePanel() async throws {
        var longRelay = ProviderDescriptor.makeOpenRelay(
            name: "Anthropic Claude Pro Max Workspace 超长名称渲染测试",
            baseURL: "https://long-name-visual.test/v1"
        )
        longRelay.id = "relay-visual-long-name"
        longRelay.enabled = true

        var pendingKimi = ProviderDescriptor.defaultOfficialKimi()
        pendingKimi.id = "kimi-visual-pending"
        pendingKimi.enabled = true

        let cacheDirectory = try makeTemporaryDirectory(named: "menu-cached-longname")
        let cache = makeSnapshotCache(
            directory: cacheDirectory,
            entries: [
                longRelay.id: makeCachedSeedSnapshot(source: longRelay.id, remaining: 27, used: 73, limit: 100),
            ]
        )

        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [longRelay, pendingKimi]),
            appUpdateService: NoopVisualAppUpdateService(),
            providerFactory: StubVisualSnapshotFactory(snapshotsByProviderID: [:], errorsByProviderID: [:]),
            persistedSnapshotCache: cache
        )

        XCTAssertEqual(viewModel.snapshots[longRelay.id]?.valueFreshness, .cachedFallback)
        XCTAssertNil(viewModel.snapshots[pendingKimi.id], "Provider without cache entry must stay pending")
        XCTAssertNil(viewModel.errors[longRelay.id])

        try renderPNG(
            MenuContentView(viewModel: viewModel, onOpenSettings: nil),
            fileName: "menu-cached-longname.png",
            proposedSize: NSSize(width: 340, height: 800),
            fitToNaturalSize: true
        )
    }

    // MARK: - Scenario 5: settings official provider detail (credential collapsed)

    func testRenderSettingsOfficialDetailCollapsed() async throws {
        let context = try await makeSettingsDetailContext(idSuffix: "collapsed")

        XCTAssertEqual(context.viewModel.snapshots[context.provider.id]?.valueFreshness, .live)
        XCTAssertEqual(context.viewModel.codexProfiles.count, 0, "Kimi detail must not import local codex accounts")

        try renderPNG(
            settingsDetailPane(
                settingsView: context.settingsView,
                provider: context.provider
            ),
            fileName: "settings-official-collapsed.png"
        )
    }

    // MARK: - Scenario 6: settings credential disclosure expanded

    func testRenderSettingsCredentialDisclosureExpanded() async throws {
        let context = try await makeSettingsDetailContext(idSuffix: "expanded")
        let settingsView = context.settingsView
        let provider = context.provider
        let viewModel = context.viewModel

        let snapshot = viewModel.snapshots[provider.id]
        let spec = ProviderSettingsSpec.resolve(for: provider)
        XCTAssertFalse(spec.credentialFields.isEmpty, "Kimi must declare a bearer credential field")

        let facade = SettingsProviderConfigurationFacade(viewModel: viewModel)
        let hasSavedCredential = facade.hasToken(for: provider)
        let expandedDisclosure = SettingsCredentialDisclosureBlock(
            headerTitle: SettingsCredentialDisclosurePresenter.headerTitle(
                hasSavedCredential: hasSavedCredential,
                language: viewModel.language
            ),
            isExpanded: Binding<Bool>(get: { true }, set: { _ in })
        ) {
            ForEach(spec.credentialFields) { field in
                VStack(alignment: .leading, spacing: 5) {
                    settingsView.settingsConfigRow(
                        title: settingsView.officialConfigCredentialTitle(for: field),
                        nested: true
                    ) {
                        settingsView.officialConfigCredentialField(
                            field,
                            provider: provider,
                            sourceMode: .auto,
                            webMode: .disabled,
                            quotaDisplayMode: .remaining,
                            traeValueDisplayMode: nil
                        )
                    }

                    if let hint = settingsView.officialCredentialHint(for: field, provider: provider) {
                        settingsView.thirdPartyHintText(hint)
                    }
                }
            }
        }

        // Same detail page order as the production page (doc §10.3) with the
        // credential block forced open through its external-binding init.
        let detailContent = ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsView.officialSubscriptionHeader(provider)
                settingsView.providerDetailStatusSection(provider, snapshot: snapshot, error: viewModel.errors[provider.id])
                settingsView.officialSubscriptionAccountsSection(provider: provider, snapshot: snapshot, error: viewModel.errors[provider.id])
                settingsView.officialSubscriptionUsageSection(provider: provider, snapshot: snapshot)
                settingsView.providerDetailProvenanceSection(provider, snapshot: snapshot)
                settingsView.settingsConfigurationSection(title: viewModel.localizedText("配置", "Configuration")) {
                    VStack(alignment: .leading, spacing: 8) {
                        settingsView.settingsDetailGroupCaption(
                            viewModel.localizedText("凭证与调试信息", "Credentials & Debug")
                        )
                        expandedDisclosure
                    }
                }
            }
            .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, alignment: .leading)
            .padding(.leading, SettingsVisualTokens.SettingsLayout.rowHeight)
            .padding(.trailing, SettingsVisualTokens.SettingsLayout.rowHeight)
            .padding(.top, SettingsVisualTokens.SettingsLayout.rowHeight)
            .padding(.bottom, SettingsVisualTokens.SettingsLayout.rowHeight)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)

        try renderPNG(
            settingsWindowCanvas {
                HStack(alignment: .top, spacing: 0) {
                    settingsView.officialSubscriptionsSidebar
                        .frame(width: 188)
                        .frame(maxHeight: .infinity, alignment: .topLeading)

                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1)

                    detailContent
                }
            },
            fileName: "settings-credential-expanded.png"
        )
    }

    // MARK: - Temporary probe

    struct PreferenceProbeView: View {
        @State private var measured: CGFloat = 0
        var body: some View {
            VStack(spacing: 8) {
                Text("header text").font(.system(size: 14)).foregroundStyle(.white)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("card \(i) title").font(.system(size: 14)).foregroundStyle(.white)
                                Text("card \(i) subtitle").font(.system(size: 11)).foregroundStyle(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ProbeHeightKey.self, value: proxy.size.height)
                        }
                    )
                }
                .scrollIndicators(.never)
                .frame(height: measured > 0 ? measured : 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onPreferenceChange(ProbeHeightKey.self) { height in
                    measured = height
                }
            }
            .padding(10)
            .background(Color(white: 0.137))
        }
    }

    struct ProbeHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    func testProbeTextRender() throws {
        try renderPNG(
            PreferenceProbeView(),
            fileName: "probe.png",
            proposedSize: NSSize(width: 340, height: 800),
            fitToNaturalSize: true
        )
    }

    // MARK: - Live menu view model (factory-filled snapshots)

    private func makeLiveMenuViewModel(language: AppLanguage, idSuffix: String) async throws -> AppViewModel {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.id = "codex-visual-live-\(idSuffix)"
        codex.enabled = true

        var relay = ProviderDescriptor.makeOpenRelay(name: "小狸云中转", baseURL: "https://xiaoliyun-visual.test/v1")
        relay.id = "relay-visual-live-\(idSuffix)"
        relay.enabled = true

        var kimi = ProviderDescriptor.defaultOfficialKimi()
        kimi.id = "kimi-visual-live-\(idSuffix)"
        kimi.enabled = true

        let now = Date()
        let snapshots: [String: UsageSnapshot] = [
            codex.id: makeLiveSnapshot(
                source: codex.id,
                remaining: 61,
                used: 39,
                limit: 100,
                unit: "%",
                sourceLabel: "API",
                accountLabel: "Pro 账号",
                quotaWindows: [
                    UsageQuotaWindow(
                        id: "\(codex.id)-5h",
                        title: "5h",
                        remainingPercent: 61,
                        usedPercent: 39,
                        resetAt: now.addingTimeInterval(2 * 3_600),
                        kind: .session,
                        resetSource: .official,
                        observedAt: now,
                        confidence: .confirmed
                    ),
                    UsageQuotaWindow(
                        id: "\(codex.id)-weekly",
                        title: "周",
                        remainingPercent: 74,
                        usedPercent: 26,
                        resetAt: now.addingTimeInterval(3 * 24 * 3_600),
                        kind: .weekly,
                        resetSource: .official,
                        observedAt: now,
                        confidence: .confirmed
                    ),
                ]
            ),
            relay.id: makeLiveSnapshot(
                source: relay.id,
                remaining: 12.5,
                used: 37.5,
                limit: 50,
                unit: "$",
                sourceLabel: "API"
            ),
            kimi.id: makeLiveSnapshot(
                source: kimi.id,
                remaining: 82,
                used: 18,
                limit: 100,
                unit: "%",
                sourceLabel: "API",
                quotaWindows: [
                    UsageQuotaWindow(
                        id: "\(kimi.id)-5h",
                        title: "5h",
                        remainingPercent: 82,
                        usedPercent: 18,
                        resetAt: now.addingTimeInterval(3 * 3_600),
                        kind: .session,
                        resetSource: .official,
                        observedAt: now,
                        confidence: .confirmed
                    )
                ]
            ),
        ]

        // Isolate every codex-state seam from the real machine: slot store,
        // profile store and desktop auth all point at an empty temp directory
        // so no real local Codex account data can leak into the render.
        let isolationRoot = try makeTemporaryDirectory(named: "menu-live-\(idSuffix)")
        let viewModel = AppViewModel(
            testingConfig: AppConfig(language: language, providers: [codex, relay, kimi]),
            appUpdateService: NoopVisualAppUpdateService(),
            codexSlotStore: CodexAccountSlotStore(fileURL: isolationRoot.appendingPathComponent("codex_slots.json")),
            codexProfileStore: CodexAccountProfileStore(fileURL: isolationRoot.appendingPathComponent("codex_profiles.json")),
            codexDesktopAuthService: CodexDesktopAuthService(homeDirectory: { isolationRoot.path }),
            providerFactory: StubVisualSnapshotFactory(snapshotsByProviderID: snapshots, errorsByProviderID: [:])
        )

        // Only refresh the providers this scenario owns; the site-defaults
        // migrator appends disabled catalog entries to the testing config and
        // those must stay untouched.
        for descriptor in viewModel.config.providers where descriptor.enabled {
            await viewModel.refreshProvider(descriptor, forceRefresh: true)
        }

        // The codex refresh upserted a slot through the real slot store path;
        // attach a placeholder profile so the official group card is visible.
        let slotID = try XCTUnwrap(
            viewModel.codexSlots.first?.slotID,
            "Codex refresh must create a slot through the injected slot store"
        )
        viewModel.codexProfiles = [
            CodexAccountProfile(
                slotID: slotID,
                displayName: "主力 Codex 账号",
                note: nil,
                authJSON: "{\"OPENAI_API_KEY\": \"sk-***test-placeholder\"}",
                accountEmail: "user@example.test",
                lastImportedAt: now,
                isCurrentSystemAccount: true
            )
        ]

        return viewModel
    }

    // MARK: - Settings detail context (kimi official provider)

    private struct SettingsDetailContext {
        let viewModel: AppViewModel
        let settingsView: SettingsView
        let provider: ProviderDescriptor
    }

    private func makeSettingsDetailContext(idSuffix: String) async throws -> SettingsDetailContext {
        var kimi = ProviderDescriptor.defaultOfficialKimi()
        kimi.id = "kimi-visual-settings-\(idSuffix)"
        kimi.enabled = true

        let now = Date()
        let snapshot = makeLiveSnapshot(
            source: kimi.id,
            remaining: 82,
            used: 18,
            limit: 100,
            unit: "%",
            sourceLabel: "API",
            accountLabel: "user@example.test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "\(kimi.id)-5h",
                    title: "5h",
                    remainingPercent: 82,
                    usedPercent: 18,
                    resetAt: now.addingTimeInterval(3 * 3_600),
                    kind: .session,
                    resetSource: .official,
                    observedAt: now,
                    confidence: .confirmed
                )
            ]
        )

        // Isolate codex seams even though kimi never touches them: the VM init
        // itself syncs local codex profiles on every construction.
        let isolationRoot = try makeTemporaryDirectory(named: "settings-\(idSuffix)")
        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [kimi]),
            appUpdateService: NoopVisualAppUpdateService(),
            codexSlotStore: CodexAccountSlotStore(fileURL: isolationRoot.appendingPathComponent("codex_slots.json")),
            codexProfileStore: CodexAccountProfileStore(fileURL: isolationRoot.appendingPathComponent("codex_profiles.json")),
            codexDesktopAuthService: CodexDesktopAuthService(homeDirectory: { isolationRoot.path }),
            providerFactory: StubVisualSnapshotFactory(
                snapshotsByProviderID: [kimi.id: snapshot],
                errorsByProviderID: [:]
            )
        )

        await viewModel.refreshProvider(viewModel.config.providers[0], forceRefresh: true)
        XCTAssertEqual(viewModel.snapshots[kimi.id]?.valueFreshness, .live)

        let settingsView = SettingsView(viewModel: viewModel)
        return SettingsDetailContext(viewModel: viewModel, settingsView: settingsView, provider: viewModel.config.providers[0])
    }

    /// Replicates the real two-pane official providers page layout
    /// (`settingsOfficialSubscriptionsPage`) around a given detail content.
    private func settingsDetailPane(
        settingsView: SettingsView,
        provider: ProviderDescriptor
    ) -> some View {
        settingsWindowCanvas {
            HStack(alignment: .top, spacing: 0) {
                settingsView.officialSubscriptionsSidebar
                    .frame(width: 188)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)

                ScrollView {
                    settingsView.officialSubscriptionDetailPage(provider)
                        .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, alignment: .leading)
                        .padding(.leading, SettingsVisualTokens.SettingsLayout.rowHeight)
                        .padding(.trailing, SettingsVisualTokens.SettingsLayout.rowHeight)
                        .padding(.top, SettingsVisualTokens.SettingsLayout.rowHeight)
                        .padding(.bottom, SettingsVisualTokens.SettingsLayout.rowHeight)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.never)
            }
        }
    }

    /// Settings window canvas: real content size 1000x720 (SettingsWindowController),
    /// dark appearance, panel background from the production theme.
    private func settingsWindowCanvas<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: 1000, height: 720)
            .background(Color(hex: 0x232323))
            .environment(\.colorScheme, .dark)
    }

    // MARK: - Rendering

    /// Renders the production view by installing it in an offscreen hosting
    /// window and capturing it with `cacheDisplay`. `ImageRenderer` is not
    /// usable here: a preference-driven `@State` write during its render pass
    /// (MenuContentView's cards-height measurement) leaves the ScrollView
    /// content unpainted, so the captured image shows only the panel chrome.
    /// A real hosting install settles layout/lifecycle like the running app.
    @discardableResult
    private func renderPNG(
        _ view: some View,
        fileName: String,
        proposedSize: NSSize? = nil,
        fitToNaturalSize: Bool = false
    ) throws -> URL {
        let initialSize = proposedSize ?? NSSize(width: 800, height: 600)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false

        let hostingView = NSHostingView(rootView: AnyView(view))
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        func settle() {
            hostingView.layoutSubtreeIfNeeded()
            for _ in 0..<30 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            hostingView.layoutSubtreeIfNeeded()
        }
        settle()

        if fitToNaturalSize {
            var natural = hostingView.fittingSize
            if natural.width < 1 || natural.height < 1 {
                natural = initialSize
            }
            let size = NSSize(
                width: proposedSize?.width ?? natural.width,
                height: natural.height
            )
            window.setContentSize(size)
            settle()
        }

        let bounds = hostingView.bounds
        let scale: CGFloat = 3
        guard bounds.width > 2, bounds.height > 2 else {
            throw NSError(domain: "MenuVisualSnapshotRendering", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(fileName): content laid out to \(bounds.size)"])
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "MenuVisualSnapshotRendering", code: 1, userInfo: [NSLocalizedDescriptionKey: "bitmap rep allocation failed for \(fileName)"])
        }
        rep.size = bounds.size

        hostingView.cacheDisplay(in: bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MenuVisualSnapshotRendering", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed for \(fileName)"])
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let url = Self.outputDirectory.appendingPathComponent(fileName)
        try png.write(to: url)

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let byteCount = (attributes[.size] as? Int) ?? 0
        XCTAssertGreaterThan(byteCount, 20_000, "\(fileName) must be a substantial render, got \(byteCount) bytes")
        print("[visual-snapshot] \(url.path) (\(byteCount) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh) px)")
        return url
    }

    // MARK: - Snapshot / cache helpers

    private func makeLiveSnapshot(
        source: String,
        remaining: Double,
        used: Double,
        limit: Double,
        unit: String,
        sourceLabel: String,
        accountLabel: String? = nil,
        quotaWindows: [UsageQuotaWindow] = [],
        updatedAt: Date = Date()
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            updatedAt: updatedAt,
            note: "ok",
            quotaWindows: quotaWindows,
            sourceLabel: sourceLabel,
            accountLabel: accountLabel
        )
    }

    /// Seed payload for the persisted snapshot cache. After cold-start restore
    /// these come back as `cachedFallback` with their fetch health preserved.
    private func makeCachedSeedSnapshot(
        source: String,
        remaining: Double,
        used: Double,
        limit: Double,
        updatedAt: Date = Date()
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: remaining,
            used: used,
            limit: limit,
            unit: "%",
            updatedAt: updatedAt,
            note: "ok",
            sourceLabel: "API"
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageVisualSnapshotTests", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSnapshotCache(
        directory: URL,
        entries: [String: UsageSnapshot]
    ) -> PersistedSnapshotCache {
        let cache = PersistedSnapshotCache(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("provider_snapshots.json")
        )
        for (providerID, snapshot) in entries {
            cache.save(providerID: providerID, snapshot: snapshot)
        }
        return cache
    }
}

// MARK: - Test doubles

private actor NoopVisualAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw ProviderError.unavailable("unused")
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw ProviderError.unavailable("unused")
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
    }
}

private struct StubVisualSnapshotFactory: ProviderFactorying {
    let snapshotsByProviderID: [String: UsageSnapshot]
    let errorsByProviderID: [String: Error]

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        StubVisualUsageProvider(
            descriptor: descriptor,
            snapshot: snapshotsByProviderID[descriptor.id],
            error: errorsByProviderID[descriptor.id]
        )
    }
}

private struct StubVisualUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot?
    let error: Error?

    func fetch() async throws -> UsageSnapshot {
        if let error {
            throw error
        }
        guard let snapshot else {
            throw ProviderError.timeout("no stub snapshot configured")
        }
        return snapshot
    }
}
