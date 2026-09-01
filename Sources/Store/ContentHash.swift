import CryptoKit
import Foundation

/// SHA-256 of clip content, used as both the dedupe key and the blob filename.
///
/// Deliberately a cryptographic digest rather than `Hashable.hashValue`. Swift
/// seeds its hasher per process, so a `hashValue` written to disk in one launch
/// compares unequal to the same content in the next — a dedupe index built on it
/// silently stops deduplicating at every restart, and, being content-addressed
/// storage, would collide blobs across launches too.
enum ContentHash {

    /// Lowercase hex, 64 characters.
    static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes text by its UTF-8 bytes, so the same string always hashes the same
    /// way regardless of how it was stored.
    static func hex(of string: String) -> String {
        hex(of: Data(string.utf8))
    }

    /// True for a well-formed key. Used to reject anything that could escape the
    /// blob directory when a key arrives from an imported file rather than from us.
    static func isValidKey(_ key: String) -> Bool {
        key.count == 64 && key.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
