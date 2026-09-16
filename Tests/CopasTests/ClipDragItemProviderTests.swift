import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Copas

@MainActor
struct ClipDragItemProviderTests {

    @Test func imageItemProviderRegistersExpectedTypes() async throws {
        let png = Fixtures.pngData(width: 30, height: 30)
        let provider = ClipDragItemProvider.itemProvider(forImageData: png, id: "test-clip-12345678")

        // Must register PNG representation
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))

        // Load data representation
        let loadedData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        #expect(loadedData == png)
    }

    @Test func textItemProviderRegistersPlainText() async throws {
        let text = "Hello from Copas clipboard"
        let provider = ClipDragItemProvider.itemProvider(forText: text)

        #expect(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))

        let loaded = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            _ = provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let str = item as? String {
                    continuation.resume(returning: str)
                } else if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: str)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        #expect(loaded == text)
    }
}
