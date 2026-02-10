import SwiftUI
import FirebaseAuth

struct AddLedgerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var auth: AuthManager
    @State private var title: String = ""
    @State private var participantName: String = ""
    @State private var participants: [Person] = []
    @State private var showingDeleteBlocked = false
    @State private var blockedName: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var onSave: (Ledger) -> Void
    private let existingLedger: Ledger?

    init(ledger: Ledger? = nil, onSave: @escaping (Ledger) -> Void) {
        self.onSave = onSave
        self.existingLedger = ledger
        _title = State(initialValue: ledger?.title ?? "")
        _participants = State(initialValue: ledger?.participants ?? [])
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
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingLedger == nil ? "新建账本" : "编辑账本")
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
                    .disabled(title.isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
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
        participants.removeAll { $0.id == participant.id }
    }

    private func saveLedger() {
        guard let userId = auth.user?.uid else { return }

        isLoading = true

        let ledger: Ledger
        if let existing = existingLedger {
            ledger = Ledger(
                id: existing.id,
                title: title,
                ownerId: existing.ownerId,
                memberIds: existing.memberIds,
                participants: participants,
                expenses: existing.expenses
            )
        } else {
            ledger = Ledger(
                id: UUID(),
                title: title,
                ownerId: userId,
                memberIds: [],
                participants: participants,
                expenses: []
            )
        }

        onSave(ledger)
        isLoading = false
        dismiss()
    }
}

#Preview {
    AddLedgerView { _ in }
        .environmentObject(AuthManager())
}
