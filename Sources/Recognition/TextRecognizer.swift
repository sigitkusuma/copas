import CoreGraphics
import Foundation
import Vision

/// On-device text recognition.
///
/// Everything here runs locally through Vision. No image and no recognised text
/// leaves the machine, which for a tool that reads whatever happens to be on
/// screen is not a detail.
enum TextRecognizer {

    /// Reads the text out of an image, in reading order, or `nil` when there is
    /// none to read.
    static func recognizeText(in image: CGImage) async -> String? {
        let languages = resolvedLanguages

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    Log.app.error("text recognition failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let order = ReadingOrder.rowMajor(observations.map(\.boundingBox))
                let lines = order.compactMap { observations[$0].topCandidates(1).first?.string }

                continuation.resume(returning: lines.isEmpty ? nil : lines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            if #available(macOS 14.0, *) {
                // Vision can pick for itself; the list above stays as a prior.
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Log.app.error("text recognition handler failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Languages

    /// Resolved once. Probing costs a request, and the answer cannot change
    /// while the app is running.
    private static let resolvedLanguages: [String] = languages(
        preferred: Locale.preferredLanguages,
        supported: supportedLanguages()
    )

    /// What this machine's Vision revision can actually recognise.
    ///
    /// Asked through a probe request configured like the real one: the
    /// class-method form was deprecated in macOS 12, and the answer varies by
    /// recognition level and revision.
    static func supportedLanguages() -> [String] {
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        return (try? probe.supportedRecognitionLanguages()) ?? ["en-US"]
    }

    /// The user's own preferred languages, narrowed to what Vision supports.
    ///
    /// `VNRecognizeTextRequest` defaults to `["en-US"]` and does not detect
    /// languages on its own below macOS 14. The measured effect is lopsided:
    /// Latin-script languages are unaffected — they share a recogniser, and
    /// English correction leaves unknown words alone — but non-Latin scripts
    /// fail completely. A Japanese screenshot returned an empty string before
    /// this and exact text after.
    ///
    /// English is always kept, whatever the user's languages are: code, URLs,
    /// file paths and UI chrome are English in most screenshots regardless of
    /// the prose around them.
    ///
    /// Pure, and separate from the probe, so the resolution rules can be tested
    /// without depending on which languages this particular machine supports.
    static func languages(preferred: [String], supported: [String]) -> [String] {
        var resolved: [String] = []

        for language in preferred {
            let code = language.prefix { $0 != "-" && $0 != "_" }.lowercased()
            guard !code.isEmpty else { continue }
            let match = supported.first {
                $0.lowercased() == code || $0.lowercased().hasPrefix(code + "-")
            }
            if let match, !resolved.contains(match) {
                resolved.append(match)
            }
        }

        if !resolved.contains(where: { $0.hasPrefix("en") }),
           let english = supported.first(where: { $0.hasPrefix("en") }) {
            resolved.append(english)
        }

        return resolved.isEmpty ? ["en-US"] : resolved
    }
}
