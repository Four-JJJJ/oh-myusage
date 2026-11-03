#!/usr/bin/env swift
// Ed25519 signing for the in-app update manifest (latest.json).
//
//   swift scripts/update_signing.swift generate
//       Prints a new private key (store it as the UPDATE_SIGNING_PRIVATE_KEY
//       repository secret, never in the repo) and its public key (commit it to
//       Sources/OhMyUsage/Resources/update_signing_public_key.txt).
//
//   UPDATE_SIGNING_PRIVATE_KEY=... swift scripts/update_signing.swift sign dist/latest.json
//       Writes dist/latest.json.sig (base64 signature over the exact bytes).
//
//   swift scripts/update_signing.swift verify dist/latest.json <public-key-file>
//       Exits non-zero unless dist/latest.json.sig verifies.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func decodeKeyMaterial(_ text: String, label: String) -> Data {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = Data(base64Encoded: trimmed) else {
        fail("\(label) is missing or not base64")
    }
    return data
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "generate":
    let key = Curve25519.Signing.PrivateKey()
    print("private (UPDATE_SIGNING_PRIVATE_KEY secret): \(key.rawRepresentation.base64EncodedString())")
    print("public  (update_signing_public_key.txt):     \(key.publicKey.rawRepresentation.base64EncodedString())")

case "sign":
    guard arguments.count == 2 else { fail("usage: sign <manifest>") }
    let raw = decodeKeyMaterial(
        ProcessInfo.processInfo.environment["UPDATE_SIGNING_PRIVATE_KEY"] ?? "",
        label: "UPDATE_SIGNING_PRIVATE_KEY"
    )
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("UPDATE_SIGNING_PRIVATE_KEY is not a valid Ed25519 private key")
    }
    let manifestURL = URL(fileURLWithPath: arguments[1])
    guard let manifest = try? Data(contentsOf: manifestURL) else { fail("cannot read \(manifestURL.path)") }
    guard let signature = try? key.signature(for: manifest) else { fail("signing failed") }
    let signatureURL = manifestURL.appendingPathExtension("sig")
    do {
        try Data((signature.base64EncodedString() + "\n").utf8).write(to: signatureURL)
    } catch {
        fail("cannot write \(signatureURL.path): \(error)")
    }
    print("wrote \(signatureURL.path)")

case "verify":
    guard arguments.count == 3 else { fail("usage: verify <manifest> <public-key-file>") }
    let manifestURL = URL(fileURLWithPath: arguments[1])
    guard let manifest = try? Data(contentsOf: manifestURL),
          let signatureText = try? String(contentsOf: manifestURL.appendingPathExtension("sig"), encoding: .utf8),
          let publicText = try? String(contentsOf: URL(fileURLWithPath: arguments[2]), encoding: .utf8) else {
        fail("cannot read manifest, signature or public key")
    }
    let signature = decodeKeyMaterial(signatureText, label: "signature")
    guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: decodeKeyMaterial(publicText, label: "public key")),
          publicKey.isValidSignature(signature, for: manifest) else {
        fail("manifest signature does not verify")
    }
    print("signature ok")

default:
    fail("usage: update_signing.swift generate | sign <manifest> | verify <manifest> <public-key-file>")
}
