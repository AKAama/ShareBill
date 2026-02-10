import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AddLedgerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var ledgerStore: LedgerStore
    @State private var title: String = ""
    @State private var participantInput: String = ""
    @State private var participants: [ParticipantInfo] = []
    @State private var errorMessage: String?
    @State private var isAddingParticipant = false
    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var saveError: String?

    var onSave: ((Ledger) -> Void)?
    private let existingLedger: Ledger?
    private let db = Firestore.firestore()

    struct ParticipantInfo: Identifiable {
        let id = UUID()
        let name: String
        var status: Status
        var isLoading: Bool = false

        enum Status: Equatable {
            case idle
            case found(userId: String, name: String)
            case notFound
            case local
        }
    }

    init(ledger: Ledger? = nil, onSave: @escaping (Ledger) -> Void) {
        self.onSave = onSave
        self.existingLedger = ledger
        _title = State(initialValue: ledger?.title ?? "")
        _participants = State(initialValue: ledger?.participants.map { ParticipantInfo(name: $0.name, status: .local) } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账本名称") {
                    TextField("输入账本名称", text: $title)
                }

                Section("添加参与者") {
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(.secondary)
                        TextField("输入邮箱或用户名", text: $participantInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isAddingParticipant)

                        if isAddingParticipant {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Button {
                                addParticipant()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .disabled(participantInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("参与者 (\(participants.count))") {
                    if participants.isEmpty {
                        Text("暂无参与者，点击右侧 + 添加")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(participants) { participant in
                            HStack {
                                if participant.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    statusIcon(for: participant.status)
                                }

                                VStack(alignment: .leading) {
                                    Text(participant.name)
                                        .font(.body)

                                    switch participant.status {
                                    case .found(let userId, _):
                                        Text(userId)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    case .notFound:
                                        Text("用户未注册，将作为本地参与者")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    case .local:
                                        Text("本地参与者")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    case .idle:
                                        EmptyView()
                                    }
                                }

                                Spacer()

                                Button {
                                    removeParticipant(participant)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                if isSaving {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("保存中...")
                            Spacer()
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
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveLedger()
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
            .alert("保存成功", isPresented: $saveSuccess) {
                Button("确定") {
                    dismiss()
                }
            } message: {
                Text("账本已成功保存")
            }
            .onChange(of: saveSuccess) { _, newValue in
                if newValue {
                    // 延迟关闭，让用户看到成功提示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ParticipantInfo.Status) -> some View {
        switch status {
        case .found:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .notFound:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
        case .local:
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private func addParticipant() {
        let input = participantInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        errorMessage = nil

        // 验证是否是已注册用户
        if auth.isValidEmail(input) {
            checkUserExistsByEmail(input)
        } else if auth.isValidUsername(input) {
            checkUserExistsByUsername(input)
        } else {
            // 本地参与者：检查名字是否重复
            if participants.contains(where: { $0.name.lowercased() == input.lowercased() }) {
                errorMessage = "该参与者已添加"
                return
            }
            let participant = ParticipantInfo(name: input, status: .notFound, isLoading: false)
            participants.append(participant)
            participantInput = ""
        }
    }

    private func checkUserExistsByEmail(_ email: String) {
        isAddingParticipant = true

        db.collection("users")
            .whereField("email", isEqualTo: email.lowercased())
            .getDocuments { snapshot, error in
                self.isAddingParticipant = false
                self.participantInput = ""

                if let error = error {
                    print("查询用户失败: \(error.localizedDescription)")
                    self.errorMessage = "查询失败，请重试"
                    return
                }

                if let doc = snapshot?.documents.first,
                   let username = doc.data()["username"] as? String {
                    let userId = doc.documentID

                    // 检查该用户是否已添加
                    if self.isUserAlreadyAdded(userId: userId) {
                        self.errorMessage = "该用户已添加 (\(username))"
                    } else {
                        let participant = ParticipantInfo(
                            name: username,
                            status: .found(userId: userId, name: username),
                            isLoading: false
                        )
                        self.participants.append(participant)
                    }
                } else {
                    // 用户未注册，添加为本地参与者
                    if self.participants.contains(where: { $0.name.lowercased() == email.lowercased() }) {
                        self.errorMessage = "该参与者已添加"
                    } else {
                        let participant = ParticipantInfo(name: email, status: .notFound, isLoading: false)
                        self.participants.append(participant)
                        self.errorMessage = "该邮箱未注册，将作为本地参与者"
                    }
                }
            }
    }

    private func checkUserExistsByUsername(_ username: String) {
        isAddingParticipant = true

        db.collection("users")
            .whereField("username", isEqualTo: username.lowercased())
            .getDocuments { snapshot, error in
                self.isAddingParticipant = false
                self.participantInput = ""

                if let error = error {
                    print("查询用户失败: \(error.localizedDescription)")
                    self.errorMessage = "查询失败，请重试"
                    return
                }

                if let doc = snapshot?.documents.first {
                    let userId = doc.documentID

                    // 检查该用户是否已添加
                    if self.isUserAlreadyAdded(userId: userId) {
                        self.errorMessage = "该用户已添加 (\(username))"
                    } else {
                        let participant = ParticipantInfo(
                            name: username,
                            status: .found(userId: userId, name: username),
                            isLoading: false
                        )
                        self.participants.append(participant)
                    }
                } else {
                    // 用户名不存在，添加为本地参与者
                    if self.participants.contains(where: { $0.name.lowercased() == username.lowercased() }) {
                        self.errorMessage = "该参与者已添加"
                    } else {
                        let participant = ParticipantInfo(name: username, status: .notFound, isLoading: false)
                        self.participants.append(participant)
                        self.errorMessage = "用户名不存在，将作为本地参与者"
                    }
                }
            }
    }

    private func isUserAlreadyAdded(userId: String) -> Bool {
        participants.contains { participant in
            if case .found(let existingId, _) = participant.status {
                return existingId == userId
            }
            return false
        }
    }

    private func updateParticipantStatus(name: String, status: ParticipantInfo.Status) {
        if let index = participants.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            participants[index].status = status
            participants[index].isLoading = false
        }
    }

    private func removeParticipant(_ participant: ParticipantInfo) {
        participants.removeAll { $0.id == participant.id }
        if participants.isEmpty {
            errorMessage = nil
        }
    }

    private func saveLedger() {
        print("=== saveLedger 调试 ===")
        print("auth.user: \(String(describing: auth.user))")
        print("auth.user?.uid: \(String(describing: auth.user?.uid))")
        print("Auth.auth().currentUser: \(String(describing: Auth.auth().currentUser))")
        print("Auth.auth().currentUser?.uid: \(String(describing: Auth.auth().currentUser?.uid))")

        // 优先使用 auth.user，如果为空则尝试从 Firebase Auth 获取
        var userId = auth.user?.uid

        // 如果本地 user 为 nil，尝试直接获取 Firebase Auth 的当前用户
        if userId == nil {
            userId = Auth.auth().currentUser?.uid
        }

        guard let validUserId = userId else {
            errorMessage = "用户未登录"
            return
        }

        isSaving = true
        errorMessage = nil

        // 将参与者转换为 Person 对象
        // 已注册用户保存 uid 到 userId 字段，本地参与者 userId 为 nil
        let persons = participants.map { p -> Person in
            let name: String
            let userId: String?
            switch p.status {
            case .found(let firebaseUid, let foundName):
                name = foundName
                userId = firebaseUid
                print("已注册用户: name=\(name), userId=\(firebaseUid)")
            case .notFound, .local, .idle:
                name = p.name
                userId = nil
                print("本地参与者: name=\(name)")
            }
            return Person(id: UUID(), name: name, userId: userId)
        }

        // 获取当前用户名作为 owner 的名字
        let ownerName = auth.userProfile?.username ?? auth.userProfile?.displayName ?? "我"
        // owner 也保存 uid
        let ownerPerson = Person(id: UUID(), name: ownerName, userId: validUserId)
        print("Owner: name=\(ownerName), userId=\(validUserId)")

        let ledger: Ledger
        if let existing = existingLedger {
            ledger = Ledger(
                id: existing.id,
                title: title,
                ownerId: existing.ownerId,
                memberIds: existing.memberIds,
                participants: persons,
                expenses: existing.expenses
            )
        } else {
            // 创建新账本时，把 owner 作为第一个参与者
            var allParticipants = [ownerPerson]
            allParticipants.append(contentsOf: persons)

            print("保存账本，participants:")
            for p in allParticipants {
                print("  - name=\(p.name), id=\(p.id.uuidString)")
            }

            ledger = Ledger(
                id: UUID(),
                title: title,
                ownerId: validUserId,
                memberIds: [],
                participants: allParticipants,
                expenses: []
            )
        }

        // 调用保存回调（如果有）
        onSave?(ledger)

        // 直接调用 ledgerStore 保存
        ledgerStore.createLedger(ledger) { error in
            self.isSaving = false
            if let error = error {
                self.errorMessage = "保存失败: \(error.localizedDescription)"
            } else {
                // 保存成功后设置当前账本
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.ledgerStore.setCurrentLedger(ledger)
                }
                self.saveSuccess = true
            }
        }
    }
}

#Preview {
    AddLedgerView { _ in }
        .environmentObject(AuthManager())
}
