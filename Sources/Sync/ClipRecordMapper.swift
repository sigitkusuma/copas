import Foundation
import CloudKit

struct DownloadedClipPayload: Sendable {
    let record: ClipRecord
    let blobData: Data?
    let rtfData: Data?
    let htmlData: Data?
}

enum ClipRecordMapper {
    static let recordType = "Clip"

    static func ckRecord(
        from clip: ClipRecord,
        zoneID: CKRecordZone.ID,
        blobs: BlobStore
    ) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: clip.id, zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        record["kind"] = clip.kind.rawValue as NSNumber
        record["clipCreatedAt"] = clip.createdAt as NSNumber
        record["sourceBundleID"] = clip.sourceBundleID as NSString?
        record["sourceAppName"] = clip.sourceAppName as NSString?
        record["preview"] = clip.preview as NSString
        record["contentHash"] = clip.contentHash as NSString
        record["byteSize"] = clip.byteSize as NSNumber
        record["charCount"] = clip.charCount as NSNumber
        record["isInline"] = (clip.isInline ? 1 : 0) as NSNumber
        record["inlineText"] = clip.inlineText as NSString?
        record["pixelWidth"] = clip.pixelWidth.map { $0 as NSNumber }
        record["pixelHeight"] = clip.pixelHeight.map { $0 as NSNumber }
        record["recognizedText"] = clip.recognizedText as NSString?
        record["recognizedAt"] = clip.recognizedAt.map { $0 as NSNumber }
        record["isPinned"] = (clip.isPinned ? 1 : 0) as NSNumber

        if let blobKey = clip.blobKey, blobs.contains(blobKey) {
            let fileURL = try blobs.url(for: blobKey)
            record["blobAsset"] = CKAsset(fileURL: fileURL)
        }
        if let rtfKey = clip.rtfKey, blobs.contains(rtfKey) {
            let fileURL = try blobs.url(for: rtfKey)
            record["rtfAsset"] = CKAsset(fileURL: fileURL)
        }
        if let htmlKey = clip.htmlKey, blobs.contains(htmlKey) {
            let fileURL = try blobs.url(for: htmlKey)
            record["htmlAsset"] = CKAsset(fileURL: fileURL)
        }

        return record
    }

    static func clipRecord(
        from ckRecord: CKRecord
    ) -> DownloadedClipPayload {
        let id = ckRecord.recordID.recordName
        let kindRaw = (ckRecord["kind"] as? NSNumber)?.intValue ?? 0
        let kind = ClipKind(rawValue: kindRaw) ?? .text
        let createdAt = (ckRecord["clipCreatedAt"] as? NSNumber)?.doubleValue
            ?? ckRecord.creationDate?.timeIntervalSince1970
            ?? Date().timeIntervalSince1970
        let sourceBundleID = ckRecord["sourceBundleID"] as? String
        let sourceAppName = ckRecord["sourceAppName"] as? String
        let preview = ckRecord["preview"] as? String ?? ""
        let contentHash = ckRecord["contentHash"] as? String ?? ""
        let byteSize = (ckRecord["byteSize"] as? NSNumber)?.intValue ?? 0
        let charCount = (ckRecord["charCount"] as? NSNumber)?.intValue ?? 0
        let isInline = ((ckRecord["isInline"] as? NSNumber)?.intValue ?? 0) != 0
        let inlineText = ckRecord["inlineText"] as? String
        let pixelWidth = (ckRecord["pixelWidth"] as? NSNumber)?.intValue
        let pixelHeight = (ckRecord["pixelHeight"] as? NSNumber)?.intValue
        let recognizedText = ckRecord["recognizedText"] as? String
        let recognizedAt = (ckRecord["recognizedAt"] as? NSNumber)?.doubleValue
        let isPinned = ((ckRecord["isPinned"] as? NSNumber)?.intValue ?? 0) != 0

        var blobData: Data?
        var blobKey: String?
        if let blobAsset = ckRecord["blobAsset"] as? CKAsset, let fileURL = blobAsset.fileURL {
            if let data = try? Data(contentsOf: fileURL) {
                blobData = data
                blobKey = ContentHash.hex(of: data)
            }
        }

        var rtfData: Data?
        var rtfKey: String?
        if let rtfAsset = ckRecord["rtfAsset"] as? CKAsset, let fileURL = rtfAsset.fileURL {
            if let data = try? Data(contentsOf: fileURL) {
                rtfData = data
                rtfKey = ContentHash.hex(of: data)
            }
        }

        var htmlData: Data?
        var htmlKey: String?
        if let htmlAsset = ckRecord["htmlAsset"] as? CKAsset, let fileURL = htmlAsset.fileURL {
            if let data = try? Data(contentsOf: fileURL) {
                htmlData = data
                htmlKey = ContentHash.hex(of: data)
            }
        }

        let cloudModifiedAt = ckRecord.modificationDate?.timeIntervalSince1970

        let computedHash: String
        if !contentHash.isEmpty {
            computedHash = contentHash
        } else if let blobKey {
            computedHash = blobKey
        } else {
            computedHash = ContentHash.hex(of: Data((inlineText ?? "").utf8))
        }

        let record = ClipRecord(
            id: id,
            kind: kind,
            createdAt: createdAt,
            sourceBundleID: sourceBundleID,
            sourceAppName: sourceAppName,
            preview: preview,
            contentHash: computedHash,
            byteSize: byteSize,
            charCount: charCount,
            isInline: isInline,
            inlineText: inlineText,
            blobKey: blobKey,
            thumbKey: nil,
            rtfKey: rtfKey,
            htmlKey: htmlKey,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            recognizedText: recognizedText,
            recognizedAt: recognizedAt,
            legacyFlags: nil,
            isPinned: isPinned,
            syncStatus: "synced",
            cloudModifiedAt: cloudModifiedAt
        )

        return DownloadedClipPayload(
            record: record,
            blobData: blobData,
            rtfData: rtfData,
            htmlData: htmlData
        )
    }
}
