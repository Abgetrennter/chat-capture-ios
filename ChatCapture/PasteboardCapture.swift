// SPDX-License-Identifier: AGPL-3.0-only
import UIKit
import UniformTypeIdentifiers

enum PasteboardCapture {
    /// Called only by the explicit Paste button, never on launch or in background.
    @MainActor static func read() throws -> [CaptureItem] {
        let board = UIPasteboard.general
        let generation = board.changeCount
        let source = board.items
        guard !source.isEmpty else { throw CaptureFailure.invalid("没有可读取的剪贴板内容") }
        var result: [CaptureItem] = []
        var totalBytes = 0
        for (index, item) in source.enumerated() {
            let captured = try readItem(item, index: index + 1)
            totalBytes += captured.data?.count ?? captured.text?.utf8.count ?? 0
            guard totalBytes <= 128 * 1024 * 1024 else {
                throw CaptureFailure.invalid("本批超过 128 MiB，请减少所选消息后重试")
            }
            result.append(captured)
        }
        guard board.changeCount == generation else {
            throw CaptureFailure.invalid("读取期间剪贴板已变化，请重新粘贴")
        }
        return result
    }

    /// Reads only plain-text representations; image and file payloads are never loaded.
    @MainActor static func readTextItems() throws -> [CaptureItem] {
        let board = UIPasteboard.general
        let generation = board.changeCount
        let source = board.items
        guard !source.isEmpty else { throw CaptureFailure.invalid("没有可读取的剪贴板内容") }
        var result: [CaptureItem] = []
        var totalBytes = 0
        for item in source {
            for key in ["public.utf8-plain-text", "public.plain-text", "public.text"] {
                guard let value = text(item[key]) else { continue }
                totalBytes += value.utf8.count
                guard totalBytes <= 128 * 1024 * 1024 else {
                    throw CaptureFailure.invalid("文字超过 128 MiB，请减少所选消息后重试")
                }
                result.append(.text(value))
                break
            }
        }
        guard board.changeCount == generation else {
            throw CaptureFailure.invalid("读取期间剪贴板已变化，请重新粘贴")
        }
        guard !result.isEmpty else { throw CaptureFailure.invalid("剪贴板中没有可导出的纯文本节点") }
        return result
    }

    private static func text(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? Data { return String(data: value, encoding: .utf8) }
        return nil
    }

    private static func readItem(_ item: [String: Any], index: Int) throws -> CaptureItem {
        // wx.file.name is metadata, never a chat text representation.
        if let bytes = item["wx.file.data"] as? Data {
            let name = text(item["wx.file.name"]) ?? "file_\(index).bin"
            let ext = (name as NSString).pathExtension.lowercased()
            let safeExt = ext.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) == nil ? "bin" : ext
            return .asset(bytes, name: name, fileExtension: safeExt)
        }
        for key in ["public.utf8-plain-text", "public.plain-text", "public.text"] {
            if let value = text(item[key]) { return .text(value) }
        }
        // Multiple UTIs are representations of ONE item, not additional messages.
        let preferred = ["public.jpeg", "public.png", "com.compuserve.gif", "org.webmproject.webp",
                         "public.heic", "public.heif", "public.image", "com.adobe.pdf", "public.file-url"]
        let keys = preferred.filter { item[$0] != nil } + item.keys.sorted().filter { !preferred.contains($0) }
        for key in keys where key != "wx.file.name" {
            let value = item[key]
            let type = UTType(key)
            let ext = type?.preferredFilenameExtension ?? "bin"
            if let bytes = value as? Data, key != "public.file-url" {
                return .asset(bytes, name: "item_\(index).\(ext)", fileExtension: ext)
            }
            if let image = value as? UIImage, let bytes = image.pngData() {
                // UIImage has no original byte representation. Preserve a lossless PNG.
                return .asset(bytes, name: "item_\(index).png", fileExtension: "png")
            }
            let url = (value as? URL) ?? text(value).flatMap { URL(string: $0) }
            if key == "public.file-url", let url = url, url.isFileURL {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bytes = try Data(contentsOf: url)
                let suffix = url.pathExtension.lowercased()
                let safe = suffix.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) == nil ? "bin" : suffix
                return .asset(bytes, name: url.lastPathComponent, fileExtension: safe)
            }
            if key == "public.url", let url = url { return .text(url.absoluteString) }
        }
        throw CaptureFailure.invalid("第 \(index) 个节点无法读取（\(item.keys.sorted().joined(separator: ", "))）；未跳过节点，请保留原聊天后重试")
    }
}
