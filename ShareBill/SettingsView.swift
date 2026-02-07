//
//  SettingsView.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingResetPasswordAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingReauthenticateSheet = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if let user = auth.user {
                    Section("账户") {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(user.displayName ?? "用户")
                                    .font(.headline)
                                Text(user.email ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        HStack {
                            Text("邮箱")
                            Spacer()
                            Text(user.email ?? "")
                                .foregroundStyle(.secondary)
                        }

                        Button("重置密码") {
                            resetPassword()
                        }
                        .disabled(isLoading)
                    }
                }

                Section("外观") {
                    Picker("主题", selection: $themeManager.currentTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                }

                Section("数据") {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Text("导出与清除")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        HStack {
                            Spacer()
                            Text("退出登录")
                            Spacer()
                        }
                    }
                }

                Section("危险操作") {
                    Button(role: .destructive) {
                        showingReauthenticateSheet = true
                    } label: {
                        Text("删除账户")
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Text("隐私政策")
                    }

                    Link(destination: URL(string: "https://example.com/terms")!) {
                        Text("服务条款")
                    }

                    HStack {
                        Spacer()
                        Text("© Alex_yehui")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .alert(alertTitle, isPresented: $showingResetPasswordAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert("删除账户", isPresented: $showingDeleteAccountAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("此操作不可逆，删除后所有数据将无法恢复。")
            }
            .sheet(isPresented: $showingReauthenticateSheet) {
                ReauthenticateView(onSuccess: {
                    showingDeleteAccountAlert = true
                })
            }
        }
    }

    private func resetPassword() {
        guard let user = auth.user, let email = user.email else { return }
        isLoading = true
        auth.resetPassword(email: email) { error in
            isLoading = false
            if let error = error {
                alertTitle = "错误"
                alertMessage = error.localizedDescription
            } else {
                alertTitle = "重置邮件已发送"
                alertMessage = "请检查您的邮箱，按照邮件指示重置密码。"
            }
            showingResetPasswordAlert = true
        }
    }

    private func deleteAccount() {
        isLoading = true
        auth.deleteAccount { error in
            isLoading = false
            if let error = error {
                alertTitle = "错误"
                alertMessage = error.localizedDescription
                showingResetPasswordAlert = true
            }
        }
    }
}

struct ReauthenticateView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    let onSuccess: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("请重新输入密码以确认身份") {
                    TextField("邮箱", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)

                    SecureField("密码", text: $password)
                        .textContentType(.password)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        reauthenticate()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("确认")
                            }
                            Spacer()
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                }
            }
            .navigationTitle("验证身份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let userEmail = auth.user?.email {
                    email = userEmail
                }
            }
        }
    }

    private func reauthenticate() {
        isLoading = true
        errorMessage = ""
        auth.reauthenticate(email: email, password: password) { error in
            isLoading = false
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                dismiss()
                onSuccess()
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
        .environmentObject(ThemeManager())
}
