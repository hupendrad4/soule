import Foundation
import CryptoKit
import Security

final class EncryptionService: Sendable {
    static let shared = EncryptionService()

    private init() {}

    private var encryptionKey: SymmetricKey {
        let tag = "com.soulo.audioKey".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecReturnData as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data(Array($0)) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        return key
    }

    func encryptAudio(at sourceURL: URL, entryId: String) async throws -> URL {
        let key = encryptionKey
        let audioData = try Data(contentsOf: sourceURL)
        let sealedBox = try AES.GCM.seal(audioData, using: key)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let encryptedDir = docs.appending(path: "audio_encrypted")
        try FileManager.default.createDirectory(at: encryptedDir, withIntermediateDirectories: true)
        let destURL = encryptedDir.appending(path: "\(entryId).enc")

        var container = Data()
        container.append(contentsOf: [0x56, 0x53, 0x41, 0x01]) // magic: "VSA" v1
        container.append(sealedBox.nonce.data)
        container.append(sealedBox.ciphertext)
        container.append(sealedBox.tag)
        try container.write(to: destURL, options: .completeFileProtectionUnlessOpen)

        return destURL
    }

    func decryptAudio(at encryptedURL: URL) async throws -> Data {
        let key = encryptionKey
        let data = try Data(contentsOf: encryptedURL)

        var offset = 0
        let magic = data[offset..<offset+4]; offset += 4
        guard magic.starts(with: [0x56, 0x53, 0x41]) else { throw EncryptionError.invalidFormat }

        let nonceData = data[offset..<offset+12]; offset += 12
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let ciphertext = data[offset..<data.count-16]
        let tag = data[data.count-16..<data.count]

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    func encryptBackup(_ data: Data, passphrase: String) throws -> Data {
        let salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = PBKDF2SHA256.deriveKey(from: passphrase, salt: salt, iterations: 100_000)

        let iv = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        var container = Data()
        container.append(Data([0x56, 0x53, 0x42, 0x4B, 0x01])) // "VSBK" v1
        container.append(UInt32(100_000).data)
        container.append(salt)
        container.append(iv)
        container.append(sealedBox.ciphertext)
        container.append(sealedBox.tag)
        return container
    }

    func decryptBackup(_ data: Data, passphrase: String) throws -> Data {
        var offset = 0
        guard data[offset..<offset+5].elementsEqual([0x56, 0x53, 0x42, 0x4B, 0x01]) else {
            throw EncryptionError.invalidFormat
        }
        offset += 5

        let iterations = Int(UInt32(data: Data(data[offset..<offset+4])))
        offset += 4
        let salt = data[offset..<offset+32]; offset += 32
        let iv = data[offset..<offset+12]; offset += 12
        let ciphertext = data[offset..<data.count-16]
        let tag = data[data.count-16..<data.count]

        let key = PBKDF2SHA256.deriveKey(from: passphrase, salt: salt, iterations: iterations)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }
}

enum EncryptionError: Error, LocalizedError {
    case invalidFormat
    case keyNotFound
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid encrypted file format"
        case .keyNotFound: return "Encryption key not found"
        case .decryptionFailed: return "Decryption failed"
        }
    }
}

// MARK: - PBKDF2 (simplified, uses CommonCrypto under the hood)

enum PBKDF2SHA256 {
    static func deriveKey(from passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        var derivedKey = Data(repeating: 0, count: 32)
        derivedKey.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase, passphrase.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    keyBytes.bindMemory(to: UInt8.self).baseAddress, 32
                )
            }
        }
        return SymmetricKey(data: derivedKey)
    }
}

extension UInt32 {
    var data: Data {
        withUnsafeBytes(of: self.bigEndian) { Data($0) }
    }
}
