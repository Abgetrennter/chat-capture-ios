// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Ordered text and asset items with portable asset paths.
struct CaptureItem {
    let text: String?
    let data: Data?
    let name: String?
    let fileExtension: String?

    static func text(_ value: String) -> CaptureItem {
        CaptureItem(text: value, data: nil, name: nil, fileExtension: nil)
    }

    static func asset(_ data: Data, name: String, fileExtension: String) -> CaptureItem {
        CaptureItem(text: nil, data: data, name: name, fileExtension: fileExtension)
    }
}

enum CaptureFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum CaptureArchive {
    /// Joins only text nodes, retaining their text and inserting a line break between nodes.
    static func plainText(from items: [CaptureItem]) -> String {
        var parts: [String] = []
        var endsWithNewline = false
        for item in items {
            guard let value = item.text else { continue }
            parts.append(value)
            if !value.isEmpty { endsWithNewline = value.hasSuffix("\n") }
            if !endsWithNewline { parts.append("\n"); endsWithNewline = true }
        }
        return parts.joined()
    }

    static func write(items: [CaptureItem], device: String, to destination: URL) throws {
        guard !items.isEmpty else { throw CaptureFailure.invalid("剪贴板为空") }
        var entries: [(String, Data)] = []
        var records: [Data] = []
        var assets: [[String: String]] = []
        var textCount = 0
        for item in items {
            if let value = item.text {
                records.append(try JSONSerialization.data(withJSONObject: ["t": "text", "v": value]))
                textCount += 1
            } else if let data = item.data {
                let ext = item.fileExtension ?? "bin"
                guard ext.range(of: "^[a-zA-Z0-9]{1,12}$", options: .regularExpression) != nil else {
                    throw CaptureFailure.invalid("资产扩展名不合法")
                }
                let filename = "asset_\(assets.count + 1).\(ext)"
                let name = item.name ?? filename
                entries.append(("assets/" + filename, data))
                records.append(try JSONSerialization.data(withJSONObject: [
                    "t": "asset", "file": "assets/" + filename, "name": name
                ]))
                assets.append(["file": filename, "originalName": name, "status": "ok"])
            } else {
                throw CaptureFailure.invalid("存在无法保存的节点；未生成不完整捕获包")
            }
        }
        let plain = plainText(from: items)
        var jsonl = Data()
        for record in records { jsonl.append(record); jsonl.append(10) }
        let manifest: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "device": device, "wechat": "unknown", "textItems": textCount, "assets": assets
        ]
        entries += [
            ("items.jsonl", jsonl), ("plain.txt", Data(plain.utf8)),
            ("manifest.json", try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]))
        ]
        guard entries.reduce(0, { $0 + $1.1.count }) <= 128 * 1024 * 1024 else {
            throw CaptureFailure.invalid("捕获包展开后超过 128 MiB，请分批捕获")
        }
        try StoredZIP.write(entries: entries, to: destination)
    }
}

/// Small ZIP writer using STORE (no recompression of JPEGs, no external package).
/// Limits are explicit; ZIP64 is intentionally not supported by this capture tool.
enum StoredZIP {
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return crc ^ 0xffffffff
    }

    static func write(entries: [(String, Data)], to destination: URL) throws {
        guard entries.count < Int(UInt16.max) else { throw CaptureFailure.invalid("文件数量超限") }
        var archive = Data()
        var central = Data()
        for (name, data) in entries {
            let filename = Data(name.utf8)
            guard filename.count < Int(UInt16.max),
                  archive.count + data.count + filename.count + 30 < Int(UInt32.max) else {
                throw CaptureFailure.invalid("捕获包超过 ZIP32 范围")
            }
            let offset = UInt32(archive.count)
            let size = UInt32(data.count)
            let checksum = crc32(data)
            archive.le32(0x04034b50); archive.le16(20); archive.le16(0x0800)
            archive.le16(0); archive.le16(0); archive.le16(33) // 1980-01-01
            archive.le32(checksum); archive.le32(size); archive.le32(size)
            archive.le16(UInt16(filename.count)); archive.le16(0)
            archive.append(filename); archive.append(data)
            central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x0800)
            central.le16(0); central.le16(0); central.le16(33)
            central.le32(checksum); central.le32(size); central.le32(size)
            central.le16(UInt16(filename.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(0); central.le32(offset)
            central.append(filename)
        }
        guard archive.count + central.count < Int(UInt32.max) else {
            throw CaptureFailure.invalid("捕获包超过 ZIP32 范围")
        }
        let start = UInt32(archive.count)
        archive.append(central)
        archive.le32(0x06054b50); archive.le16(0); archive.le16(0)
        archive.le16(UInt16(entries.count)); archive.le16(UInt16(entries.count))
        archive.le32(UInt32(central.count)); archive.le32(start); archive.le16(0)
        try archive.write(to: destination, options: .atomic)
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8))
    }
    mutating func le32(_ value: UInt32) {
        le16(UInt16(truncatingIfNeeded: value)); le16(UInt16(truncatingIfNeeded: value >> 16))
    }
}
