import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("登录云端")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("使用和桌面账本、手机 PWA 相同的账号")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "person")
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 18)
                            TextField("账号", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                        }
                        .padding(.vertical, 14)

                        Divider().overlay(AppTheme.hairline)

                        HStack(spacing: 12) {
                            Image(systemName: "lock")
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 18)
                            SecureField("密码", text: $password)
                                .textContentType(.password)
                        }
                        .padding(.vertical, 14)
                    }
                    .padding(.horizontal, 16)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.hairline, lineWidth: 0.5)
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            if isBusy {
                                ProgressView().tint(.white)
                            }
                            Text(isBusy ? "登录中…" : "登录")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isBusy || username.isEmpty || password.isEmpty)

                    Text("密码只用于这一次登录请求，不会保存在本机；登录成功后只保存云端会话 Token。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(AppTheme.grouped.ignoresSafeArea())
            .navigationTitle("账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        isBusy = true
        errorMessage = nil
        let error = await store.login(username: username, password: password)
        isBusy = false
        if let error {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}
