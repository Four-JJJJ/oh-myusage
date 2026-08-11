import Foundation
import OhMyUsageApplication
import OhMyUsageBootstrap
import OhMyUsageDomain
import OhMyUsageFeatures
import OhMyUsageInfrastructure
import OhMyUsagePresentation
import XCTest

final class ArchitectureTargetBoundaryTests: XCTestCase {
    func testNonExecutableTargetsKeepDependencyDirection() throws {
        let rules: [(directory: String, forbiddenImports: [String])] = [
            (
                "Sources/OhMyUsageDomain",
                ["OhMyUsage", "OhMyUsageApplication", "OhMyUsageInfrastructure", "OhMyUsageProviders", "OhMyUsagePresentation", "OhMyUsageFeatures", "OhMyUsageBootstrap", "SwiftUI", "AppKit", "Security", "LocalAuthentication"]
            ),
            (
                "Sources/OhMyUsageInfrastructure",
                ["OhMyUsage", "OhMyUsageApplication", "OhMyUsageProviders", "OhMyUsagePresentation", "OhMyUsageFeatures", "OhMyUsageBootstrap", "SwiftUI", "AppKit"]
            ),
            (
                "Sources/OhMyUsageProviders",
                ["OhMyUsage", "OhMyUsageApplication", "OhMyUsageInfrastructure", "OhMyUsagePresentation", "OhMyUsageFeatures", "OhMyUsageBootstrap", "SwiftUI", "AppKit"]
            ),
            (
                "Sources/OhMyUsageApplication",
                ["OhMyUsage", "OhMyUsageInfrastructure", "OhMyUsageProviders", "OhMyUsagePresentation", "OhMyUsageFeatures", "OhMyUsageBootstrap", "SwiftUI", "AppKit"]
            ),
            (
                "Sources/OhMyUsagePresentation",
                ["OhMyUsage", "OhMyUsageApplication", "OhMyUsageInfrastructure", "OhMyUsageProviders", "OhMyUsageFeatures", "OhMyUsageBootstrap", "AppKit"]
            ),
            (
                "Sources/OhMyUsageFeatures",
                ["OhMyUsage", "OhMyUsageBootstrap"]
            ),
            (
                "Sources/OhMyUsageBootstrap",
                ["OhMyUsage"]
            )
        ]

        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for rule in rules {
            let directoryURL = rootURL.appendingPathComponent(rule.directory)
            let sourceFiles = try swiftFiles(in: directoryURL)
            for sourceFile in sourceFiles {
                let source = try String(contentsOf: sourceFile, encoding: .utf8)
                let importedModules = importedModuleNames(in: source)
                for forbiddenImport in rule.forbiddenImports {
                    XCTAssertFalse(
                        importedModules.contains(forbiddenImport),
                        "\(sourceFile.path) should not import \(forbiddenImport)"
                    )
                }
            }
        }
    }

    func testPackageManifestKeepsNonExecutableTargetsOnAllowedLayerDependencies() throws {
        let targets = try packageManifestTargets()
        let expectedDependencies: [String: Set<String>] = [
            "OhMyUsageDomain": [],
            "OhMyUsageInfrastructure": ["OhMyUsageDomain"],
            "OhMyUsageProviders": ["OhMyUsageDomain"],
            "OhMyUsageApplication": ["OhMyUsageDomain"],
            "OhMyUsagePresentation": ["OhMyUsageDomain"],
            "OhMyUsageFeatures": ["OhMyUsageDomain", "OhMyUsageApplication", "OhMyUsagePresentation"],
            "OhMyUsageBootstrap": ["OhMyUsageDomain", "OhMyUsageApplication", "OhMyUsageFeatures", "OhMyUsagePresentation"]
        ]

        let nonExecutableTargets = targets.values.filter { $0.kind == .regular }
        XCTAssertEqual(
            Set(nonExecutableTargets.map(\.name)),
            Set(expectedDependencies.keys),
            "Package.swift should keep non-executable target boundaries explicit; update this guard when adding a layer target"
        )

        for (targetName, dependencies) in expectedDependencies {
            let target = try XCTUnwrap(
                targets[targetName],
                "Package.swift should declare a regular target named \(targetName)"
            )
            XCTAssertEqual(target.kind, .regular)
            XCTAssertEqual(
                target.dependencies,
                dependencies,
                "\(targetName) should keep the current one-way package dependency boundary"
            )
        }
    }

    func testPackageManifestPinsCurrentBroadExecutableAndTestDependencies() throws {
        let targets = try packageManifestTargets()
        let executableTarget = try XCTUnwrap(
            targets["OhMyUsage"],
            "Package.swift should declare the executable target"
        )
        let testTarget = try XCTUnwrap(
            targets["OhMyUsageTests"],
            "Package.swift should declare the test target"
        )
        let executableAllowedDependencies: Set<String> = [
            "OhMyUsageDomain",
            "OhMyUsageInfrastructure",
            "OhMyUsageProviders",
            "OhMyUsageApplication",
            "OhMyUsagePresentation",
            "OhMyUsageFeatures",
            "OhMyUsageBootstrap"
        ]
        let testAllowedDependencies = executableAllowedDependencies.union(["OhMyUsage"])

        XCTAssertEqual(executableTarget.kind, .executable)
        XCTAssertEqual(
            executableTarget.dependencies,
            executableAllowedDependencies,
            "TODO boundary guard: the executable target is still broadly wired. Do not widen it; when composition narrows, update this allowlist with the new boundary."
        )
        XCTAssertEqual(testTarget.kind, .test)
        XCTAssertEqual(
            testTarget.dependencies,
            testAllowedDependencies,
            "TODO boundary guard: the test target currently imports the full stack for architecture coverage. Do not widen it without documenting why."
        )
    }

    func testPackageNonExecutableTargetsDoNotImportUIFrameworks() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let targets = try packageManifestTargets()
        let forbiddenUIImports: Set<String> = ["SwiftUI", "AppKit"]

        for target in targets.values where target.kind == .regular {
            let directoryURL = rootURL.appendingPathComponent("Sources/\(target.name)")
            let sourceFiles = try swiftFiles(in: directoryURL)
            for sourceFile in sourceFiles {
                let source = try String(contentsOf: sourceFile, encoding: .utf8)
                let importedSpecifiers = importedImportSpecifiers(in: source)
                let forbiddenImports = forbiddenUIImports.intersection(importedSpecifiers)

                XCTAssertTrue(
                    forbiddenImports.isEmpty,
                    "\(sourceFile.path) is in non-executable target \(target.name) and should not import UI frameworks directly: \(forbiddenImports.sorted())"
                )
            }
        }
    }

    func testRuntimeDiagnosticsDarwinMachImportStaysExplicitlyAllowlisted() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let targets = try packageManifestTargets()
        let expectedExceptions: [String: Set<String>] = [
            "Sources/OhMyUsageApplication/RuntimeDiagnostics.swift": ["Darwin.Mach"]
        ]
        var observedExceptions: [String: Set<String>] = [:]

        for target in targets.values where target.kind == .regular {
            let directoryURL = rootURL.appendingPathComponent("Sources/\(target.name)")
            let sourceFiles = try swiftFiles(in: directoryURL)
            for sourceFile in sourceFiles {
                let source = try String(contentsOf: sourceFile, encoding: .utf8)
                let exceptionalImports = importedImportSpecifiers(in: source).intersection(["Darwin.Mach"])
                guard !exceptionalImports.isEmpty else {
                    continue
                }
                observedExceptions[relativePath(for: sourceFile, rootURL: rootURL)] = exceptionalImports
            }
        }

        XCTAssertEqual(
            observedExceptions,
            expectedExceptions,
            "RuntimeDiagnostics.swift may keep the current Darwin.Mach diagnostics import; add a focused allowlist entry before introducing another non-executable platform exception"
        )
    }

    func testBootstrapAndFeatureAssemblyExposePureUsageCompositionWithoutRuntimeIntegration() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let featureAssemblyURL = rootURL.appendingPathComponent("Sources/OhMyUsageFeatures/UsageFeatureAssembly.swift")
        let compositionRootURL = rootURL.appendingPathComponent("Sources/OhMyUsageBootstrap/OhMyUsageCompositionRoot.swift")
        let featureAssembly = try String(contentsOf: featureAssemblyURL, encoding: .utf8)
        let compositionRoot = try String(contentsOf: compositionRootURL, encoding: .utf8)

        let providerID = try XCTUnwrap(UsageProviderIdentity("codex"))
        let snapshot = UsageQuotaSnapshot(
            used: 32,
            limit: 80,
            capturedAtUnixSeconds: 1_700_000_000
        )
        let assembly = UsageFeatureAssembly()
        let descriptor = assembly.makeUsageFeatureDescriptor(
            providerID: providerID,
            title: "Codex",
            defaultForceRefresh: true
        )
        let request = assembly.makeRefreshRequest(for: descriptor)
        let summary = assembly.makeSummaryViewState(for: descriptor, snapshot: snapshot)
        let composition = OhMyUsageCompositionRoot(featureAssembly: assembly)
        let composedRequest = composition.makeUsageRefreshRequest(for: descriptor, forceRefresh: false)
        let composedSummary = composition.makeUsageSummaryViewState(for: descriptor, snapshot: snapshot)

        XCTAssertEqual(descriptor.providerID, providerID)
        XCTAssertEqual(descriptor.title, "Codex")
        XCTAssertTrue(descriptor.defaultForceRefresh)
        XCTAssertEqual(request.providerID, providerID)
        XCTAssertTrue(request.forceRefresh)
        XCTAssertEqual(summary.providerID, providerID)
        XCTAssertEqual(summary.title, "Codex")
        XCTAssertEqual(summary.usageRatio, 0.4)
        XCTAssertEqual(composedRequest.providerID, providerID)
        XCTAssertFalse(composedRequest.forceRefresh)
        XCTAssertEqual(composedSummary, summary)

        XCTAssertTrue(featureAssembly.contains("makeRefreshRequest"))
        XCTAssertTrue(featureAssembly.contains("makeSummaryViewState"))
        XCTAssertTrue(compositionRoot.contains("makeUsageRefreshRequest"))
        XCTAssertTrue(compositionRoot.contains("makeUsageSummaryViewState"))
        XCTAssertTrue(
            compositionRoot.contains("AppCompositionFactory"),
            "Bootstrap docs should clarify that executable App wiring lives in AppCompositionFactory"
        )
        XCTAssertTrue(
            compositionRoot.contains("AppDependencyGraph"),
            "Bootstrap docs should clarify that executable App wiring lives in AppDependencyGraph"
        )
        XCTAssertFalse(featureAssembly.contains("refreshUseCaseTypeName"))
        XCTAssertFalse(featureAssembly.contains("summaryViewStateTypeName"))

        for completeRuntimeResponsibility in [
            "AppViewModel",
            "StatusBarController",
            "SettingsWindowController",
            "NSApplication",
            "ProviderDescriptor",
            "makeApplication",
            "makeAppViewModel",
            "makeProvider",
            "startRuntime"
        ] {
            XCTAssertFalse(
                featureAssembly.contains(completeRuntimeResponsibility),
                "UsageFeatureAssembly should stay a pure value assembly boundary and must not claim complete runtime integration through \(completeRuntimeResponsibility)"
            )
            XCTAssertFalse(
                compositionRoot.contains(completeRuntimeResponsibility),
                "OhMyUsageCompositionRoot should stay a bootstrap composition boundary and must not claim complete runtime integration through \(completeRuntimeResponsibility)"
            )
        }
    }

    func testNonExecutableTargetsExposeExplicitResponsibilities() throws {
        let requiredResponsibilityFiles: [(directory: String, files: Set<String>)] = [
            (
                "Sources/OhMyUsageDomain",
                [
                    "AuthModels.swift",
                    "OfficialProviderConfigModels.swift",
                    "OpenRelayProviderConfigModels.swift",
                    "ProviderFamily.swift",
                    "ProviderType.swift",
                    "RelayModels.swift",
                    "UsageProviderIdentity.swift",
                    "UsageQuotaSnapshot.swift",
                    "UsageSnapshot.swift"
                ]
            ),
            (
                "Sources/OhMyUsageInfrastructure",
                ["UsageCredentialStore.swift", "CredentialStoring.swift"]
            ),
            (
                "Sources/OhMyUsageProviders",
                [
                    "UsageProviderFetching.swift",
                    "ProviderError.swift",
                    "OfficialSnapshotFallback.swift",
                    "OfficialProviderFetchRuntime.swift",
                    "OfficialProviderAuthRuntime.swift",
                    "RelayHTTPClient.swift",
                    "OfficialValueParser.swift",
                    "JWTInspector.swift",
                    "WebOverlayRetryBackoff.swift",
                    "LocalJSONFileReader.swift",
                    "LocalJSONFileReading.swift",
                    "ShellCommand.swift",
                    "ShellCommandRunning.swift",
                    "SQLiteShell.swift",
                    "SQLiteQuerying.swift",
                    "RelayJSONExpressionEvaluator.swift",
                    "TokenCredentialStoring.swift",
                    "BrowserCookieDetecting.swift",
                    "BrowserCredentialProviding.swift",
                    "KimiBrowserCookieDetecting.swift"
                ]
            ),
            (
                "Sources/OhMyUsageApplication",
                [
                    "ProviderRefreshScheduler.swift",
                    "RefreshUseCaseContracts.swift",
                    "CodexQuotaDisplayNormalizer.swift"
                ]
            ),
            (
                "Sources/OhMyUsagePresentation",
                [
                    "UsagePresentationModels.swift",
                    "OfficialMonitoringHealthPresenter.swift",
                    "QuotaBlockagePolicy.swift"
                ]
            ),
            (
                "Sources/OhMyUsageFeatures",
                ["UsageFeatureAssembly.swift", "UsageFeatureDescriptor.swift"]
            ),
            (
                "Sources/OhMyUsageBootstrap",
                ["OhMyUsageCompositionRoot.swift"]
            )
        ]

        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for requirement in requiredResponsibilityFiles {
            let directoryURL = rootURL.appendingPathComponent(requirement.directory)
            let sourceFiles = try swiftFiles(in: directoryURL)
            let fileNames = Set(sourceFiles.map(\.lastPathComponent))
            let matchingFiles = fileNames.intersection(requirement.files)

            XCTAssertFalse(
                matchingFiles.isEmpty,
                "\(requirement.directory) should expose at least one explicit responsibility file, not only module markers"
            )

            let nonMarkerFiles = sourceFiles.filter { !isModuleMarkerFile($0) }
            XCTAssertFalse(
                nonMarkerFiles.isEmpty,
                "\(requirement.directory) should contain a compilable non-marker boundary type"
            )
        }
    }

    func testLayerBoundaryTypesAreImportableByArchitectureTests() throws {
        let providerID = try XCTUnwrap(UsageProviderIdentity("codex"))
        let snapshot = UsageQuotaSnapshot(
            used: 25,
            limit: 100,
            capturedAtUnixSeconds: 1_700_000_000
        )
        let request = UsageRefreshRequest(providerID: providerID, forceRefresh: true)
        let providerType = ProviderType.codex
        let quotaWindow = UsageQuotaWindow(
            id: "session",
            title: "5h",
            remainingPercent: 75,
            usedPercent: 25,
            resetAt: Date(timeIntervalSince1970: 1_700_000_100),
            kind: .session
        )
        let usageSnapshot = UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 75,
            used: 25,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: "ok",
            quotaWindows: [quotaWindow],
            sourceLabel: "API"
        )
        let summary = UsageProviderSummaryViewState(
            providerID: providerID,
            title: "Codex",
            snapshot: snapshot
        )
        let featureAssembly = UsageFeatureAssembly()
        let compositionRoot = OhMyUsageCompositionRoot(featureAssembly: featureAssembly)

        XCTAssertEqual(request.providerID, providerID)
        XCTAssertEqual(providerType.rawValue, "codex")
        XCTAssertEqual(snapshot.remaining, 75)
        XCTAssertEqual(usageSnapshot.quotaWindows.first?.resetSource, .official)
        XCTAssertEqual(usageSnapshot.quotaWindows.first?.confidence, .confirmed)
        XCTAssertEqual(summary.usageRatio, 0.25)
        XCTAssertEqual(
            compositionRoot.makeUsageSummaryViewState(providerID: providerID, title: "Codex", snapshot: snapshot),
            summary
        )

        let normalized = CodexQuotaDisplayNormalizer.normalize(
            snapshot: usageSnapshot,
            isActive: false,
            now: Date(timeIntervalSince1970: 1_700_000_200)
        )
        XCTAssertEqual(normalized.quotaWindows.first?.kind, .session)

        let healthPercents = OfficialMonitoringHealthPresenter.quotaMetricPercents(
            for: quotaWindow,
            displaysUsedQuota: false
        )
        XCTAssertEqual(healthPercents.healthPercent, 75)
        XCTAssertEqual(
            OfficialMonitoringHealthPresenter.officialMonitoringHealthStatus(
                snapshot: usageSnapshot,
                healthPercents: [healthPercents.healthPercent]
            ),
            .sufficient
        )
        XCTAssertFalse(
            QuotaBlockagePolicy.isBlockedByDepletedWeeklyQuota(
                currentKind: .session,
                currentRemainingPercent: 75,
                candidateWindows: [(kind: .weekly, remainingPercent: 40, isAvailable: true)]
            )
        )
        XCTAssertEqual(CredentialStoreServiceNames.defaultServiceName, "oh-myusage")
        XCTAssertTrue(CredentialStoreServiceNames.isLegacyServiceName("OhMyUsage"))
    }

    func testProviderConfigurationValueObjectsAreOwnedByDomainTarget() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let domainURL = rootURL.appendingPathComponent("Sources/OhMyUsageDomain")
        let executableModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models")

        let expectedDomainFiles = [
            "AuthModels.swift",
            "OfficialProviderConfigModels.swift",
            "RelayModels.swift",
            "OpenRelayProviderConfigModels.swift"
        ]
        for fileName in expectedDomainFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: domainURL.appendingPathComponent(fileName).path),
                "Stage 1 provider configuration value objects should live in OhMyUsageDomain/\(fileName)"
            )

            let legacyExecutableModelURL = executableModelsURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: legacyExecutableModelURL.path) {
                let source = try String(contentsOf: legacyExecutableModelURL, encoding: .utf8)
                for ownedTypeDefinition in [
                    "enum AuthKind",
                    "struct AuthConfig",
                    "struct AlertRule",
                    "enum OfficialSourceMode",
                    "enum OfficialWebMode",
                    "enum OfficialQuotaDisplayMode",
                    "enum OfficialTraeValueDisplayMode",
                    "struct OfficialProviderConfig",
                    "struct RelayProviderConfig",
                    "enum RelayCredentialMode",
                    "struct RelayManualOverride",
                    "enum RelayAuthStrategyKind",
                    "struct RelayAuthStrategy",
                    "struct RelayAdapterMatch",
                    "enum RelayRequiredInputKind",
                    "struct RelaySetupManifest",
                    "struct RelayRequestManifest",
                    "struct RelayTokenRequestManifest",
                    "struct RelayExtractManifest",
                    "enum RelayPostprocessID",
                    "struct RelayAdapterManifest",
                    "struct OpenProviderConfig",
                    "struct RelayAccountBalanceConfig"
                ] {
                    XCTAssertFalse(
                        source.contains(ownedTypeDefinition),
                        "Legacy executable model file \(fileName) may be absent or exist only as a compatibility shim; it must not own \(ownedTypeDefinition)"
                    )
                }
            }
        }

        let credential = AuthConfig(
            kind: .bearer,
            keychainService: "manual-service",
            keychainAccount: "account@example.com"
        )
        let alertRule = AlertRule(
            lowRemaining: 12.5,
            maxConsecutiveFailures: 3,
            notifyOnAuthError: true
        )
        let officialConfig = OfficialProviderConfig(
            sourceMode: .web,
            webMode: .manual,
            manualCookieAccount: "manual-cookie",
            oauthAccountImportEnabled: false,
            autoDiscoveryEnabled: false,
            quotaDisplayMode: .used,
            traeValueDisplayMode: .amount,
            showPlanTypeInMenuBar: false
        )
        let manualOverride = try JSONDecoder().decode(
            RelayManualOverride.self,
            from: Data(
                """
                {
                  "authHeader": "Authorization",
                  "authScheme": "Bearer",
                  "userID": "u-1",
                  "userIDHeader": "X-User",
                  "requestMethod": "POST",
                  "requestBodyJSON": "{\\"range\\":\\"month\\"}",
                  "endpointPath": "/api/quota",
                  "remainingExpression": "$.remaining",
                  "usedExpression": "$.used",
                  "limitExpression": "$.limit",
                  "successExpression": "$.ok",
                  "unitExpression": "$.unit",
                  "accountLabelExpression": "$.account",
                  "staticHeaders": { "X-Test": "1" }
                }
                """.utf8
            )
        )
        let relayConfig = RelayProviderConfig(
            adapterID: "new-api",
            baseURL: "https://relay.example.com",
            tokenChannelEnabled: false,
            balanceChannelEnabled: true,
            balanceAuth: credential,
            balanceCredentialMode: .browserPreferred,
            quotaDisplayMode: .used,
            manualOverrides: manualOverride
        )
        let adapterManifest = RelayAdapterManifest(
            id: "new-api",
            displayName: "New API",
            match: RelayAdapterMatch(hostPatterns: ["relay.example.com"], defaultDisplayName: "Relay"),
            setup: RelaySetupManifest(requiredInputs: [.displayName, .baseURL, .balanceAuth]),
            authStrategies: [RelayAuthStrategy(kind: .savedBearer)],
            displayMode: .hybrid,
            supportsBrowserFallback: false,
            supportsSeparateBalanceAuth: true,
            balanceRequest: RelayRequestManifest(path: "/api/quota"),
            tokenRequest: RelayTokenRequestManifest(),
            extract: RelayExtractManifest(remaining: "$.remaining", used: "$.used", limit: "$.limit"),
            postprocessID: .quotaDisplayStatus
        )
        let openProviderConfig = try JSONDecoder().decode(
            OpenProviderConfig.self,
            from: Data(
                """
                {
                  "tokenUsageEnabled": true,
                  "accountBalance": {
                    "enabled": true,
                    "auth": {
                      "kind": "bearer",
                      "keychainService": "manual-service",
                      "keychainAccount": "account@example.com"
                    },
                    "authHeader": "Authorization",
                    "authScheme": "Bearer",
                    "requestMethod": "GET",
                    "endpointPath": "/dashboard/billing/credit_grants",
                    "userIDHeader": "New-Api-User",
                    "remainingJSONPath": "$.total_available",
                    "usedJSONPath": "$.total_used",
                    "limitJSONPath": "$.total_granted",
                    "successJSONPath": "$.success",
                    "unit": "USD"
                  }
                }
                """.utf8
            )
        )

        XCTAssertEqual(credential.kind, .bearer)
        XCTAssertEqual(alertRule.maxConsecutiveFailures, 3)
        XCTAssertEqual(officialConfig.sourceMode, .web)
        XCTAssertEqual(relayConfig.balanceCredentialMode, .browserPreferred)
        XCTAssertEqual(relayConfig.manualOverrides?.staticHeaders?["X-Test"], "1")
        XCTAssertEqual(adapterManifest.displayMode, .hybrid)
        XCTAssertEqual(openProviderConfig.accountBalance?.unit, "USD")
    }

    func testDomainTargetDoesNotOwnProviderRuntimeOrConfigurationPolicy() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let domainURL = rootURL.appendingPathComponent("Sources/OhMyUsageDomain")
        let domainFiles = try swiftFiles(in: domainURL)

        let forbiddenPolicyFragments = [
            "ProviderDescriptor",
            "ProviderFactory",
            "ProviderDefinitionRegistry",
            "SettingsDraft",
            "struct AppConfig",
            "migratedWithSiteDefaults",
            "normalizedCredentialServiceName",
            "defaultOfficialConfig",
            "defaultRelayConfig",
            "defaultOfficialCodex",
            "relayViewConfig",
            "officialRelayDefaultProviderIDs",
            "Bundle.module",
            "Keychain",
            "LAContext",
            "NSApplication",
            "View"
        ]

        for sourceFile in domainFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for fragment in forbiddenPolicyFragments {
                XCTAssertFalse(
                    source.contains(fragment),
                    "\(relativePath(for: sourceFile, rootURL: rootURL)) should keep \(fragment) out of OhMyUsageDomain"
                )
            }
        }
    }

    func testNonExecutableTargetsDoNotReferenceExecutableCompositionTypes() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let targets = try packageManifestTargets()
        let forbiddenTypeReferences = ["AppCompositionFactory", "AppDependencyGraph"]

        for target in targets.values where target.kind == .regular {
            let directoryURL = rootURL.appendingPathComponent("Sources/\(target.name)")
            let sourceFiles = try swiftFiles(in: directoryURL)
            for sourceFile in sourceFiles {
                let source = try String(contentsOf: sourceFile, encoding: .utf8)
                let codeOnlySource = source
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///") && !trimmed.hasPrefix("*")
                    }
                    .joined(separator: "\n")

                for forbiddenType in forbiddenTypeReferences {
                    XCTAssertFalse(
                        codeOnlySource.contains(forbiddenType),
                        "\(relativePath(for: sourceFile, rootURL: rootURL)) in \(target.name) should not reference executable composition type \(forbiddenType)"
                    )
                }
            }
        }
    }

    func testProviderStateStoreWritesAreOwnedByRefreshModel() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let refreshModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppProviderRefreshModel.swift")
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let sessionStoreURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppSessionStore.swift")
        let refreshModel = try String(contentsOf: refreshModelURL, encoding: .utf8)
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)
        let sessionStore = try String(contentsOf: sessionStoreURL, encoding: .utf8)

        XCTAssertTrue(
            refreshModel.contains("Sole write entry"),
            "AppProviderRefreshModel should document that it owns the sole ProviderStateStore write entry"
        )
        XCTAssertTrue(refreshModel.contains("func mutateProviderState("))
        XCTAssertTrue(refreshModel.contains("func replaceProviderState("))
        XCTAssertTrue(
            appViewModel.contains("func applyProviderStateStorage(_ state: ProviderStateStore)"),
            "AppViewModel must expose the physical Observation write helper for refresh-model setState"
        )
        XCTAssertTrue(
            appViewModel.contains("self?.applyProviderStateStorage(state)"),
            "Provider refresh bind setState must route through applyProviderStateStorage"
        )
        XCTAssertTrue(
            sessionStore.contains("Logical writes must go through `AppProviderRefreshModel`"),
            "ProviderStateStore should document the refresh-model write ownership boundary"
        )
        XCTAssertFalse(
            appViewModel.contains("set { sessionStore.providerState"),
            "AppViewModel provider-state projections must stay get-only; sets go through providerRefreshModel"
        )

        let appSourceFiles = try swiftFiles(in: rootURL.appendingPathComponent("Sources/OhMyUsage"))
        let forbiddenBypassPatterns: [NSRegularExpression] = try [
            #"providerStateStorage\s*=#"#,
            #"host\.snapshots\[[^\]]+\]\s*="#,
            #"host\.errors\[[^\]]+\]\s*="#,
            #"host\.consecutiveFailures\[[^\]]+\]\s*="#,
            #"host\.lastUpdatedAt\s*="#,
            #"host\.snapshots\.remove"#,
            #"host\.errors\.remove"#,
            #"host\.consecutiveFailures\.remove"#,
            #"host\.activeAlerts\.(remove|insert|removeAll)"#,
            #"host\.thirdPartyBalanceBaselineTracker\.(remove|prune|restore|removeAll)"#,
            #"self\.snapshots\.(removeAll|removeValue)"#,
            #"self\.errors\.(removeAll|removeValue)"#,
            #"self\.consecutiveFailures\.(removeAll|removeValue)"#,
            #"self\.activeAlerts\.(removeAll|remove)"#,
            #"self\.thirdPartyBalanceBaselineTracker\.(removeAll|remove|prune|restore)"#,
            #"self\.lastUpdatedAt\s*="#,
            #"self\.snapshots\[[^\]]+\]\s*="#,
            #"self\.errors\[[^\]]+\]\s*="#,
            #"self\.consecutiveFailures\[[^\]]+\]\s*="#
        ].map { try NSRegularExpression(pattern: $0) }

        for sourceFile in appSourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            let path = relativePath(for: sourceFile, rootURL: rootURL)

            if source.contains("sessionStore.providerState =") {
                XCTAssertEqual(
                    path,
                    "Sources/OhMyUsage/App/AppViewModel.swift",
                    "Physical ProviderStateStore assignment must stay inside AppViewModel.applyProviderStateStorage"
                )
                XCTAssertTrue(
                    appViewModel.contains("func applyProviderStateStorage(_ state: ProviderStateStore) {\n        sessionStore.providerState = state\n    }"),
                    "sessionStore.providerState assignment must only live in applyProviderStateStorage"
                )
            }

            // Coordinator mutates through bound getState/setState (`state.`), which is the refresh write path.
            if path == "Sources/OhMyUsage/App/AppProviderRefreshCoordinator.swift" {
                continue
            }

            let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
            for pattern in forbiddenBypassPatterns {
                XCTAssertEqual(
                    pattern.numberOfMatches(in: source, options: [], range: nsRange),
                    0,
                    "\(path) bypasses AppProviderRefreshModel provider-state ownership (matched /\(pattern.pattern)/)"
                )
            }
        }
    }
}
