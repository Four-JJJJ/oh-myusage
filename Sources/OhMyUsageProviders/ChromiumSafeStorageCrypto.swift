import CommonCrypto
import Foundation

/// Chromium "Safe Storage" cookie/secret decryption used by Chrome-family apps.
///
/// Encrypted blobs start with `v10` or `v11`, then AES-128-CBC ciphertext. The
/// key is PBKDF2-HMAC-SHA1 of the Keychain passphrase with salt `saltysalt`
/// and 1003 rounds.
public enum ChromiumSafeStorageCrypto {
    public static let versionPrefixV10 = Data([0x76, 0x31, 0x30]) // "v10"
    public static let versionPrefixV11 = Data([0x76, 0x31, 0x31]) // "v11"

    public static func derivedKey(passphrase: String) -> Data? {
        pbkdf2SHA1(password: passphrase, salt: "saltysalt", rounds: 1003, keyByteCount: 16)
    }

    public static func decrypt(_ encrypted: Data, passphrase: String) -> Data? {
        guard encrypted.count > 3 else { return nil }
        let versionPrefix = encrypted.prefix(3)
        guard versionPrefix == versionPrefixV10 || versionPrefix == versionPrefixV11 else {
            return nil
        }
        guard let key = derivedKey(passphrase: passphrase) else {
            return nil
        }
        let cipher = Data(encrypted.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        return aesCBCDecrypt(ciphertext: cipher, key: key, iv: iv)
    }

    public static func decryptUTF8(_ encrypted: Data, passphrase: String) -> String? {
        guard let decrypted = decrypt(encrypted, passphrase: passphrase) else {
            return nil
        }
        if let decoded = String(data: decrypted, encoding: .utf8), !decoded.isEmpty {
            return decoded
        }
        if decrypted.count > 32 {
            let trimmed = Data(decrypted.dropFirst(32))
            if let decoded = String(data: trimmed, encoding: .utf8), !decoded.isEmpty {
                return decoded
            }
        }
        return nil
    }

    public static func decryptBase64(_ encoded: String, passphrase: String) -> String? {
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = Data(base64Encoded: trimmed) else {
            return nil
        }
        return decryptUTF8(data, passphrase: passphrase)
    }

    private static func pbkdf2SHA1(password: String, salt: String, rounds: Int, keyByteCount: Int) -> Data? {
        guard let saltData = salt.data(using: .utf8) else {
            return nil
        }

        var keyData = Data(repeating: 0, count: keyByteCount)
        let keyLength = keyData.count
        let result = keyData.withUnsafeMutableBytes { keyBytes in
            password.utf8CString.withUnsafeBytes { passBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.bindMemory(to: Int8.self).baseAddress,
                        passBytes.count - 1,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(rounds),
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }

        return result == kCCSuccess ? keyData : nil
    }

    private static func aesCBCDecrypt(ciphertext: Data, key: Data, iv: Data) -> Data? {
        var outLength = 0
        var outData = Data(repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let outCapacity = outData.count
        let status = outData.withUnsafeMutableBytes { outBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outBytes.baseAddress,
                            outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        outData.count = outLength
        return outData
    }
}
