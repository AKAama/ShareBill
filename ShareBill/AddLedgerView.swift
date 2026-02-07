import SwiftUI

struct AddLedgerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""
    @State private var participantName: String = ""
    @State private var participants: [Person] = []
    @State private var showingDeleteBlocked = false
    @State private var blockedName: String = ""

    var onSave: (Ledger) -> Void
    private let existingId: UUID?
    private let protectedParticipantIds: Set<UUID>

    init(ledger: Ledger? = nil, onSave: @escaping (Ledger) -> Void) {
        self.onSave = onSave
        self.existingId = ledger?.id
        _title = State(initialValue: ledger?.title ?? "")
        _participants = State(initialValue: ledger?.participants ?? [])
        if let ledger = ledger {
            var ids: Set<UUID> = []
            for expense in ledger.expenses {
                ids.insert(expense.payer.id)
                for person in expense.participants {
                    ids.insert(person.id)
                }
            }
            self.protectedParticipantIds = ids
        } else {
            self.protectedParticipantIds = []
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账本名称") {
                    TextField("输入账本名称", text: $title)
                }

                Section("参与者") {
                    HStack {
                        TextField("添加参与者", text: $participantName)
                        Button("添加") {
                            addParticipant()
                        }
                        .disabled(participantName.isEmpty)
                    }

                    if participants.isEmpty {
                        Text("暂无参与者")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(participants) { participant in
                            HStack {
                                Text(participant.name)
                                Spacer()
                                Button("删除") {
                                    deleteParticipant(participant)
                                }
                                .foregroundStyle(.red)
                                .disabled(isProtected(participant))
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingId == nil ? "新建账本" : "编辑账本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveLedger()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .alert("无法删除", isPresented: $showingDeleteBlocked) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("「\(blockedName)」已出现在账单中，无法删除。")
            }
        }
    }

    private func addParticipant() {
        guard !participantName.isEmpty,
              !participants.contains(where: { $0.name == participantName }) else { return }
        participants.append(Person(name: participantName))
        participantName = ""
    }

    private func deleteParticipant(_ participant: Person) {
        if isProtected(participant) {
            blockedName = participant.name
            showingDeleteBlocked = true
        } else {
            participants.removeAll { $0.id == participant.id }
        }
    }

    private func isProtected(_ participant: Person) -> Bool {
        protectedParticipantIds.contains(participant.id)
    }

    private func saveLedger() {
        guard !title.isEmpty else { return }
        let ledger = Ledger(
            id: existingId ?? UUID(),
            title: title,
            participants: participants,
            expenses: []
        )
        onSave(ledger)
        dismiss()
    }
}

#Preview {
    AddLedgerView { _ in }
}
