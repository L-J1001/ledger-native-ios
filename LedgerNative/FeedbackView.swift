import SwiftUI
import Foundation

/// 和桌面端同一条匿名反馈通道：只发送用户亲手写的内容 + 版本/客户端等通用字段。
struct FeedbackView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var category = "功能建议"
    @State private var message = ""
    @State private var contact = ""
    @State private var sending = false
    @State private var status: String?
    @State private var showDone = false
    @State private var showError = false

    private let categories = ["功能建议", "使用问题", "界面体验", "同步与更新", "其他"]

    var body: some View {
        Form {
            Section("反馈类型") {
                Picker("类型", selection: $category) {
                    ForEach(categories, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 130)
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("写下遇到的问题或想要的功能，至少 4 个字")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("反馈内容")
            } footer: {
                Text("\(message.count)/2000 · 不会附带账目、账本名称、账号、截图或日志")
            }

            Section("联系方式（选填）") {
                TextField("邮箱 / 微信，方便回复你", text: $contact)
                    .textInputAutocapitalization(.never)
            }

            Section {
                Button {
                    send()
                } label: {
                    HStack {
                        Spacer()
                        if sending { ProgressView().padding(.trailing, 6) }
                        Text(sending ? "发送中…" : "发送反馈")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }
                }
                .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            } footer: {
                Text("反馈会进入维护工具的「意见反馈」页；不会公开展示，也不会自动上传本地文件。")
            }
        }
        .navigationTitle("意见反馈")
        .navigationBarTitleDisplayMode(.inline)
        .alert("已发送", isPresented: $showDone) {
            Button("好") { dismiss() }
        } message: {
            Text("谢谢你的建议，维护者会看到这条反馈。")
        }
        .alert("发送失败", isPresented: $showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(status ?? "网络暂时不可达，内容还在输入框里，可以稍后重试。")
        }
    }

    private func send() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 4 else { return }
        sending = true
        status = nil

        let endpoint = (store.auth?.endpoint ?? SyncService.defaultEndpoint)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: endpoint + "/v1/feedback") else {
            sending = false
            status = "服务地址不正确"
            showError = true
            return
        }
        var payload: [String: Any] = [
            "category": category,
            "message": text,
            "contact": contact.trimmingCharacters(in: .whitespacesAndNewlines),
            "website": "",
            "meta": [
                "version": "1.2.6",
                "os": "iOS",
                "client": "ios-native",
                "page": "settings_feedback"
            ]
        ]
        payload["website"] = ""

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("ledger-ios-feedback/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let ok = (json?["ok"] as? Bool) ?? false
                await MainActor.run {
                    sending = false
                    if (code == 200 || code == 201) && ok {
                        showDone = true
                    } else if code == 429 {
                        status = "提交太频繁，请过几分钟再试；内容仍保留在输入框里"
                        showError = true
                    } else if code == 409 {
                        status = "这条反馈刚刚已经提交过了，无需重复发送"
                        showError = true
                    } else {
                        status = "服务端返回 \(code)；内容还在输入框里，可以稍后重试"
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    sending = false
                    status = "网络暂时不可达；内容还在输入框里，可以稍后重试"
                    showError = true
                }
            }
        }
    }
}
