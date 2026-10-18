import Darwin
import Foundation
import XCTest
@testable import OhMyUsage

final class AppUpdateServiceTests: XCTestCase {
    override func tearDown() {
        AppUpdateMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testMetadataURLUsesLatestJsonReleaseAttachment() {
        XCTAssertEqual(AppUpdateService.owner, "Four-JJJJ")
        XCTAssertEqual(AppUpdateService.repository, "oh-myusage")
        XCTAssertEqual(AppUpdateService.legacyRepository, "AI-Plan-Monitor")
        XCTAssertEqual(
            AppUpdateService.metadataURL.absoluteString,
            "https://github.com/Four-JJJJ/oh-myusage/releases/latest/download/latest.json"
        )
        XCTAssertEqual(
            AppUpdateService.legacyMetadataURL.absoluteString,
            "https://github.com/Four-JJJJ/AI-Plan-Monitor/releases/latest/download/latest.json"
        )
    }

    func testFetchLatestReleaseParsesRepresentativeLatestJsonManifest() async throws {
        let zipURL = URL(string: "https://github.com/Four-JJJJ/oh-myusage/releases/download/v2.3.4/oh-myusage-macOS.zip")!
        let dmgURL = URL(string: "https://github.com/Four-JJJJ/oh-myusage/releases/download/v2.3.4/oh-myusage.dmg")!
        let releaseURL = URL(string: "https://github.com/Four-JJJJ/oh-myusage/releases/tag/v2.3.4")!
        let manifest = Data(
            """
            {
              "version": "v2.3.4",
              "pub_date": "2026-05-09T12:34:56Z",
              "release_url": "\(releaseURL.absoluteString)",
              "notes_url": "\(releaseURL.absoluteString)",
              "assets": {
                "macos_zip": {
                  "url": "\(zipURL.absoluteString)",
                  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "size": 123456
                },
                "macos_dmg": {
                  "url": "\(dmgURL.absoluteString)",
                  "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                  "size": 654321
                }
              }
            }
            """.utf8
        )

        let session = makeMockSession { request in
            XCTAssertEqual(request.url, AppUpdateService.metadataURL)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "OhMyUsage")

            return (
                HTTPURLResponse(
                    url: AppUpdateService.metadataURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                manifest
            )
        }
        let service = AppUpdateService(session: session)

        let update = try await service.fetchLatestRelease()

        XCTAssertEqual(update.latestVersion, "2.3.4")
        XCTAssertEqual(update.releaseURL, releaseURL)
        XCTAssertEqual(update.notesURL, releaseURL)
        XCTAssertEqual(update.publishedAt, ISO8601DateFormatter().date(from: "2026-05-09T12:34:56Z"))
        XCTAssertEqual(update.zipAsset?.url, zipURL)
        XCTAssertEqual(update.zipAsset?.sha256, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(update.zipAsset?.size, 123456)
        XCTAssertEqual(update.dmgAsset?.url, dmgURL)
        XCTAssertEqual(update.dmgAsset?.sha256, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        XCTAssertEqual(update.dmgAsset?.size, 654321)
        XCTAssertEqual(update.downloadURL, zipURL)
    }

    func testFetchLatestReleaseFallsBackToLegacyMetadataURLAfterPrimaryNetworkFailure() async throws {
        let zipURL = URL(string: "https://github.com/Four-JJJJ/oh-myusage/releases/download/v2.0.0/oh-myusage-macOS.zip")!
        let manifest = Data(
            """
            {
              "version": "2.0.0",
              "pub_date": "2026-05-09T12:34:56Z",
              "release_url": "https://github.com/Four-JJJJ/oh-myusage/releases/tag/v2.0.0",
              "assets": {
                "macos_zip": {
                  "url": "\(zipURL.absoluteString)"
                }
              }
            }
            """.utf8
        )
        var requestedURLs: [URL] = []
        let session = makeMockSession { request in
            requestedURLs.append(try XCTUnwrap(request.url))

            if request.url == AppUpdateService.metadataURL {
                return (
                    HTTPURLResponse(
                        url: AppUpdateService.metadataURL,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }

            XCTAssertEqual(request.url, AppUpdateService.legacyMetadataURL)
            return (
                HTTPURLResponse(
                    url: AppUpdateService.legacyMetadataURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                manifest
            )
        }
        let service = AppUpdateService(
            session: session,
            latestMetadataURLs: [AppUpdateService.metadataURL, AppUpdateService.legacyMetadataURL]
        )

        let update = try await service.fetchLatestRelease()

        XCTAssertEqual(update.latestVersion, "2.0.0")
        XCTAssertEqual(update.zipAsset?.url, zipURL)
        XCTAssertEqual(requestedURLs, [AppUpdateService.metadataURL, AppUpdateService.legacyMetadataURL])
    }

    func testFetchLatestReleaseRejectsInvalidMetadata() async throws {
        let session = makeMockSession { _ in
            (
                HTTPURLResponse(
                    url: AppUpdateService.metadataURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(
                    """
                    {
                      "version": "   ",
                      "pub_date": "2026-05-09T12:34:56Z",
                      "assets": {}
                    }
                    """.utf8
                )
            )
        }
        let service = AppUpdateService(session: session)

        do {
            _ = try await service.fetchLatestRelease()
            XCTFail("Expected invalid metadata to be rejected.")
        } catch AppUpdateError.invalidMetadata {
        } catch {
            XCTFail("Expected invalidMetadata, got \(error).")
        }
    }

    func testDetachedInstallerSurvivesParentProcessGroupTermination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageInstallerDetach-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let markerURL = root.appendingPathComponent("alive")
        let scriptURL = root.appendingPathComponent("install_update.sh")
        let script = """
        #!/bin/sh
        echo $$ > '\(markerURL.path)'
        sleep 30
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        try AppUpdateService.launchDetachedInstaller(scriptURL: scriptURL)

        let deadline = Date().addingTimeInterval(5)
        var pidText = ""
        while Date() < deadline {
            if let text = try? String(contentsOf: markerURL, encoding: .utf8), !text.isEmpty {
                pidText = text
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let installerPID = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertNotNil(installerPID)
        guard let installerPID else { return }
        defer { kill(installerPID, SIGKILL) }

        XCTAssertNotEqual(getpgid(installerPID), getpgrp(), "Installer must leave the app process group")
        XCTAssertEqual(kill(installerPID, 0), 0, "Installer must still be running after its launcher exits")
    }

    func testPrepareUpdateRequiresMacOSZipAsset() async throws {
        let service = AppUpdateService(session: makeMockSession { _ in
            throw URLError(.unsupportedURL)
        })
        let update = AppUpdateInfo(
            latestVersion: "2.3.4",
            releaseURL: AppUpdateService.releasesURL,
            notesURL: nil,
            publishedAt: nil,
            zipAsset: nil,
            dmgAsset: AppUpdateAsset(
                url: URL(string: "https://github.com/Four-JJJJ/oh-myusage/releases/download/v2.3.4/oh-myusage.dmg")!,
                sha256: nil,
                size: nil
            )
        )

        do {
            _ = try await service.prepareUpdate(update)
            XCTFail("Expected automatic update without a ZIP asset to fail.")
        } catch AppUpdateError.missingZipAsset {
        } catch {
            XCTFail("Expected missingZipAsset, got \(error).")
        }
    }

    func testPrepareUpdateRejectsChecksumMismatchBeforeExtraction() async throws {
        let zipURL = URL(string: "https://github.com/Four-JJJJ/oh-myusage/releases/download/v2.3.4/oh-myusage-macOS.zip")!
        let session = makeMockSession { request in
            XCTAssertEqual(request.url, zipURL)
            return (
                HTTPURLResponse(url: zipURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("not the expected zip payload".utf8)
            )
        }
        let service = AppUpdateService(session: session)
        let update = AppUpdateInfo(
            latestVersion: "2.3.4",
            releaseURL: AppUpdateService.releasesURL,
            notesURL: nil,
            publishedAt: nil,
            zipAsset: AppUpdateAsset(
                url: zipURL,
                sha256: "0000000000000000000000000000000000000000000000000000000000000000",
                size: nil
            ),
            dmgAsset: nil
        )

        do {
            _ = try await service.prepareUpdate(update)
            XCTFail("Expected checksum mismatch to stop update preparation.")
        } catch AppUpdateError.checksumMismatch {
        } catch {
            XCTFail("Expected checksumMismatch, got \(error).")
        }
    }

    private func makeMockSession(
        requestHandler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        AppUpdateMockURLProtocol.requestHandler = requestHandler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppUpdateMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class AppUpdateMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = AppUpdateMockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
