import CryptoKit
import Foundation

/// Detached Ed25519 signature over the exact bytes of `latest.json`.
///
/// The manifest and the archive it points at are served from the same GitHub
/// release, and ad-hoc builds carry no team identity to pin, so the checksum
/// alone only proves the archive matches whatever manifest was published.
/// Signing the manifest with a key that lives outside GitHub (a release
/// secret) means a substituted release cannot produce an update this app will
/// install.
///
/// The public key ships in `Resources/update_signing_public_key.txt`. While
/// that file is empty verification is off, so existing release pipelines keep
/// working until the key pair is provisioned; once it holds a key every
/// manifest must carry a valid `latest.json.sig`.
enum UpdateManifestSignature {
    static let signatureFileExtension = "sig"

    /// The embedded verification key, or `nil` while signing is not provisioned.
    static let embeddedPublicKey: Curve25519.Signing.PublicKey? = {
        guard let text = embeddedPublicKeyText() else { return nil }
        return try? publicKey(fromBase64: text)
    }()

    static func embeddedPublicKeyText() -> String? {
        guard let url = Bundle.module.url(forResource: "update_signing_public_key", withExtension: "txt") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func publicKey(fromBase64 text: String) throws -> Curve25519.Signing.PublicKey? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let raw = Data(base64Encoded: trimmed) else {
            throw AppUpdateError.manifestSignatureInvalid
        }
        return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    static func signatureURL(forManifestAt manifestURL: URL) -> URL {
        manifestURL.appendingPathExtension(signatureFileExtension)
    }

    /// `signatureFile` is the base64 text of `latest.json.sig`.
    static func verify(manifest: Data, signatureFile: Data, publicKey: Curve25519.Signing.PublicKey) throws {
        guard let text = String(data: signatureFile, encoding: .utf8),
              let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              publicKey.isValidSignature(signature, for: manifest) else {
            throw AppUpdateError.manifestSignatureInvalid
        }
    }
}
