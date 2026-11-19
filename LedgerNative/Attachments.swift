import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 本机附件：原件放在 Documents/attachments，索引放在 UserDefaults。
/// 目前不参与云端同步（同步 payload 里没有附件字段），以后可把 fileName 换成远端 URL。
struct LedgerAttachment: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var fileName: String
    var mime: String
    var size: Int

    var isImage: Bool { mime.hasPrefix("image/") }

    var sizeText: String {
        if size <= 0 { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(Int((Double(size) / 1024).rounded())) KB" }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }
}

enum LedgerAttachments {
    static let indexKey = "ledger_attach_index_v1"
    static let maxEach = 10 * 1024 * 1024
    static let maxCount = 9

    static func directory() -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func url(for item: LedgerAttachment) -> URL {
        directory().appendingPathComponent(item.fileName)
    }

    private static func index() -> [String: [LedgerAttachment]] {
        guard let data = UserDefaults.standard.data(forKey: indexKey),
              let decoded = try? JSONDecoder().decode([String: [LedgerAttachment]].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func write(_ map: [String: [LedgerAttachment]]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }
    }

    static func load(key: String) -> [LedgerAttachment] {
        guard !key.isEmpty else { return [] }
        return index()[key] ?? []
    }

    static func save(key: String, _ list: [LedgerAttachment]) {
        guard !key.isEmpty else { return }
        var map = index()
        map[key] = list
        write(map)
    }

    static func remove(key: String, id: String) {
        var map = index()
        guard var list = map[key] else { return }
        if let target = list.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: url(for: target))
        }
        list.removeAll { $0.id == id }
        map[key] = list
        write(map)
    }

    /// 从系统选择器拿到的 URL 复制进沙盒；单个 10MB 上限。
    static func importFile(from source: URL) -> LedgerAttachment? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let name = source.lastPathComponent
        let ext = source.pathExtension
        guard let data = try? Data(contentsOf: source) else { return nil }
        if data.count > maxEach { return nil }

        let id = UUID().uuidString
        let fileName = ext.isEmpty ? id : "\(id).\(ext)"
        let target = directory().appendingPathComponent(fileName)
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            return nil
        }

        let type = UTType(filenameExtension: ext)
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        return LedgerAttachment(id: id, name: name, fileName: fileName, mime: mime, size: data.count)
    }
}

struct AttachmentPreviewSheet: View {
    let item: LedgerAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if item.isImage,
                   let image = UIImage(contentsOfFile: LedgerAttachments.url(for: item).path) {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 42))
                            .foregroundStyle(AppTheme.accent)
                        Text(item.name)
                            .font(.system(size: 15, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Text(item.sizeText)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                        ShareLink(item: LedgerAttachments.url(for: item)) {
                            Label("用其他应用打开", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(AppTheme.accentSoft)
                                .clipShape(Capsule())
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("附件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
