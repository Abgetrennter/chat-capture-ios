// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import UIKit

@main
struct ChatCaptureApp: App {
    var body: some Scene { WindowGroup { CaptureView() } }
}

struct CaptureView: View {
    @State private var items: [CaptureItem] = []
    @State private var archives: [URL] = []
    @State private var sharing: URL?
    @State private var error: String?
    @State private var busy = false

    private var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Captures", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("在微信中多选复制后，回到这里选择导出方式。图文捕获包保留文字和图片；纯文本导出只拼接文字节点并跳过图片、文件数据。")
                    Button(busy ? "正在保存…" : "粘贴并保存捕获包") { capture() }
                        .disabled(busy)
                    Button(busy ? "正在保存…" : "粘贴并导出纯文本") { capturePlainText() }
                        .disabled(busy)
                    Text("仅点击时读取剪贴板。微信文字节点中原有的媒体占位说明会保留；捕获文件只保存在本机。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !items.isEmpty {
                    Section("本次预览 · \(items.count) 个节点") {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("节点 \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                if let text = item.text { Text(text).textSelection(.enabled) }
                                if let data = item.data {
                                    if let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                                    } else { Text(item.name ?? "文件") }
                                    Text("已保存资产 · \(data.count) 字节").font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("已保存的导出文件") {
                    if archives.isEmpty { Text("尚未捕获材料").foregroundStyle(.secondary) }
                    ForEach(archives, id: \.self) { url in
                        Button { sharing = url } label: {
                            Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                        }
                    }
                    Text("图文 ZIP 可能包含私人聊天和原始图片；纯文本 TXT 只包含文字节点。发送前请确认接收对象。文件可重复分享。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("聊天捕获")
            .onAppear { reload() }
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                if let url = sharing { ShareSheet(url: url) }
            }
            .alert("捕获未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    @MainActor private func capture() {
        busy = true
        do {
            let captured = try PasteboardCapture.read()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "wechat_full_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(8)).zip"
            let destination = folder.appendingPathComponent(filename)
            let device = "\(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)"
            // ZIP creation does not need UIKit or access to the live clipboard.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try CaptureArchive.write(items: captured, device: device, to: destination)
                    DispatchQueue.main.async {
                        self.items = captured; self.reload(); self.busy = false; self.sharing = destination
                    }
                } catch {
                    let message = error.localizedDescription
                    DispatchQueue.main.async { self.error = message; self.busy = false }
                }
            }
        } catch { self.error = error.localizedDescription; busy = false }
    }

    @MainActor private func capturePlainText() {
        busy = true
        do {
            let captured = try PasteboardCapture.readTextItems()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "wechat_text_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(8)).txt"
            let destination = folder.appendingPathComponent(filename)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Data(CaptureArchive.plainText(from: captured).utf8).write(to: destination, options: .atomic)
                    DispatchQueue.main.async {
                        self.items = captured; self.reload(); self.busy = false; self.sharing = destination
                    }
                } catch {
                    let message = error.localizedDescription
                    DispatchQueue.main.async { self.error = message; self.busy = false }
                }
            }
        } catch { self.error = error.localizedDescription; busy = false }
    }

    private func reload() {
        archives = ((try? FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: nil)) ?? [])
            .filter { ["zip", "txt"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
