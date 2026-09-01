import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import Copas

enum Fixtures {

    /// A solid rectangle, or a half-transparent one, encoded as PNG.
    static func pngData(width: Int, height: Int, opaque: Bool = true) -> Data {
        let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        )!

        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: opaque ? 1 : 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = context.makeImage()!
        let encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return encoded as Data
    }

    /// A PNG that carries an alpha channel whether or not anything in it is
    /// actually see-through — which is what real screenshots look like.
    static func pngDataWithAlphaChannel(width: Int, height: Int, alpha: Double) -> Data {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = context.makeImage()!
        let encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return encoded as Data
    }

    static func tiffData(width: Int, height: Int) -> Data {
        NSImage(data: pngData(width: width, height: height))!.tiffRepresentation!
    }

    /// A directory that the caller is responsible for removing.
    static func temporaryDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("copas-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A pasteboard of our own, so tests never touch what the user has copied.
    static func pasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.sigitkusuma.copas.tests.\(UUID().uuidString)"))
    }
}
