//
//  AddMemberView.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import SwiftUI

struct AddMemberView: View {
    @EnvironmentObject var ledgerStore: LedgerStore
    @Environment(\.dismiss) var dismiss
    let ledger: Ledger

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("添加成员") {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.secondary)
                        TextField("输入邮箱添加成员", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Button {
                        addMember()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("添加")
                            }
                            Spacer()
                        }
                    }
                    .disabled(email.isEmpty || isLoading)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                if let success = successMessage {
                    Section {
                        Text(success)
                            .foregroundStyle(.green)
                    }
                }

                Section("当前成员") {
                    ForEach(ledger.memberIds, id: \.self) { memberId in
                        MemberRowView(memberId: memberId, ledger: ledger)
                    }
                }
            }
            .navigationTitle("成员管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func addMember() {
        guard !email.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        ledgerStore.addMember(byEmail: email, to: ledger) { result in
            isLoading = false

            switch result {
            case .success:
                successMessage = "添加成功！"
                email = ""
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct MemberRowView: View {
    @EnvironmentObject var ledgerStore: LedgerStore
    let memberId: String
    let ledger: Ledger

    @State private var memberName: String = "加载中..."
    @State private var isRemoving = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(memberName)
                    .font(.body)
                Text(memberId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isRemoving {
                ProgressView()
            } else {
                Button(role: .destructive) {
                    removeMember()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear {
            fetchMemberName()
        }
    }

    private func fetchMemberName() {
        ledgerStore.fetchMemberNames(ids: [memberId]) { names in
            memberName = names[memberId] ?? "未知用户"
        }
    }

    private func removeMember() {
        isRemoving = true
        ledgerStore.removeMember(memberId, from: ledger) { result in
            isRemoving = false
        }
    }
}

#Preview {
    AddMemberView(ledger: Ledger(
        id: UUID(),
        title: "测试账本",
        ownerId: "owner123",
        memberIds: ["member1", "member2"]
    ))
    .environmentObject(LedgerStore())
}
