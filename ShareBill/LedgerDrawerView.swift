//
//  LedgerDrawerView.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import SwiftUI

struct LedgerDrawerView: View {
    @EnvironmentObject var ledgerStore: LedgerStore
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    let showingAddLedger: () -> Void
    let editingLedger: (Ledger) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    userHeaderView
                }

                Section {
                    if ledgerStore.ledgers.isEmpty {
                        HStack {
                            Spacer()
                            Text("暂无账本")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 40)
                    } else {
                        ForEach(ledgerStore.ledgers) { ledger in
                            ledgerRowView(ledger)
                        }
                    }
                } header: {
                    Text("我的账本")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("账本列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddLedger()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private var userHeaderView: some View {
        HStack(spacing: 12) {
            if let avatarImage = auth.userProfile?.avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(auth.userProfile?.displayName ?? "用户")
                    .font(.headline)
                if let username = auth.userProfile?.username {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func ledgerRowView(_ ledger: Ledger) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(ledger.title)
                        .font(.headline)
                    if ledgerStore.currentLedger?.id == ledger.id {
                        Text("当前")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("\(ledger.memberCount) 人")
                    if !ledger.expenses.isEmpty {
                        Text("•")
                        Text("\(ledger.expenses.count) 笔")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if ledgerStore.currentLedger?.id == ledger.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ledgerStore.setCurrentLedger(ledger)
            dismiss()
        }
        .swipeActions(edge: .leading) {
            Button {
                editingLedger(ledger)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                ledgerStore.deleteLedger(ledger)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    LedgerDrawerView(
        showingAddLedger: {},
        editingLedger: { _ in }
    )
    .environmentObject(LedgerStore())
}
