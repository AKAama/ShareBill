import Foundation
import Combine
import FirebaseFirestore

final class LedgerStore: ObservableObject {
    @Published private(set) var ledgers: [Ledger] = []
    @Published var currentLedger: Ledger?
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var currentLedgerListener: ListenerRegistration?
    private var userId: String?
    private let userDefaultsKey = "CurrentLedgerId"

    // MARK: - 绑定用户账本列表

    func bind(userId: String) {
        guard self.userId == nil || self.userId != userId else { return }

        self.userId = userId
        stop()

        // 监听用户参与的账本
        let userLedgersRef = db.collection("users").document(userId).collection("myLedgers")

        listener = userLedgersRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }

            if let error = error {
                print("Ledger listener error: \(error)")
                return
            }

            guard let snapshot = snapshot else { return }

            let ledgerIds = snapshot.documents.compactMap { doc -> String? in
                guard let ledgerId = doc.data()["ledgerId"] as? String else { return nil }
                return ledgerId
            }

            self.fetchLedgers(ids: ledgerIds)
        }
    }

    private func fetchLedgers(ids: [String]) {
        guard !ids.isEmpty else {
            ledgers = []
            currentLedger = nil
            return
        }

        isLoading = true

        let group = DispatchGroup()
        var fetchedLedgers: [Ledger] = []

        for id in ids {
            guard let uuid = UUID(uuidString: id) else { continue }

            group.enter()
            db.collection("ledgers").document(id).getDocument { [weak self] snapshot, _ in
                defer { group.leave() }

                if let doc = snapshot, doc.exists,
                   let ledger = self?.ledgerFromDocument(doc, id: uuid) {
                    fetchedLedgers.append(ledger)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.ledgers = fetchedLedgers.sorted { $0.title < $1.title }

            // 恢复当前账本
            if let savedId = UserDefaults.standard.string(forKey: self.userDefaultsKey),
               let uuid = UUID(uuidString: savedId),
               let ledger = self.ledgers.first(where: { $0.id == uuid }) {
                self.currentLedger = ledger
            } else {
                self.currentLedger = self.ledgers.first
            }

            // 监听当前账本变化
            if let currentId = self.currentLedger?.id.uuidString {
                self.listenToCurrentLedger(id: currentId)
            }
        }
    }

    private func listenToCurrentLedger(id: String) {
        currentLedgerListener?.remove()

        currentLedgerListener = db.collection("ledgers").document(id).addSnapshotListener { [weak self] snapshot, _ in
            guard let snapshot = snapshot, snapshot.exists,
                  let uuid = UUID(uuidString: id),
                  let ledger = self?.ledgerFromDocument(snapshot, id: uuid) else { return }

            DispatchQueue.main.async {
                self?.currentLedger = ledger
                if let index = self?.ledgers.firstIndex(where: { $0.id == ledger.id }) {
                    self?.ledgers[index] = ledger
                }
            }
        }
    }

    func setCurrentLedger(_ ledger: Ledger) {
        currentLedger = ledger
        UserDefaults.standard.set(ledger.id.uuidString, forKey: userDefaultsKey)
        listenToCurrentLedger(id: ledger.id.uuidString)
    }

    func stop() {
        listener?.remove()
        currentLedgerListener?.remove()
        listener = nil
        currentLedgerListener = nil
        userId = nil
        ledgers = []
        currentLedger = nil
    }

    // MARK: - 账本操作

    func createLedger(_ ledger: Ledger, completion: @escaping (Error?) -> Void) {
        guard let userId else {
            completion(NSError(domain: "LedgerStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "未登录"]))
            return
        }

        let ledgerData = ledgerToData(ledger)

        db.collection("ledgers").document(ledger.id.uuidString).setData(ledgerData) { [weak self] error in
            if let error = error {
                completion(error)
                return
            }

            // 在用户账本列表中添加
            self?.db.collection("users").document(userId)
                .collection("myLedgers")
                .document(ledger.id.uuidString)
                .setData(["joinedAt": Date().timeIntervalSince1970]) { _ in
                    completion(nil)
                }
        }
    }

    func updateLedger(_ ledger: Ledger, completion: @escaping (Error?) -> Void = { _ in }) {
        db.collection("ledgers").document(ledger.id.uuidString)
            .setData(ledgerToData(ledger), merge: true) { error in
                completion(error)
            }
    }

    func deleteLedger(_ ledger: Ledger, completion: @escaping (Error?) -> Void = { _ in }) {

        let batch = db.batch()

        // 删除账本
        batch.deleteDocument(db.collection("ledgers").document(ledger.id.uuidString))

        // 从所有成员中移除
        for memberId in ledger.memberIds {
            batch.deleteDocument(
                db.collection("users").document(memberId)
                    .collection("myLedgers").document(ledger.id.uuidString)
            )
        }

        batch.commit { [weak self] error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.ledgers.removeAll { $0.id == ledger.id }
                    if self?.currentLedger?.id == ledger.id {
                        self?.currentLedger = self?.ledgers.first
                    }
                }
            }
            completion(error)
        }
    }

    // MARK: - 成员管理

    func addMember(byEmail email: String, to ledger: Ledger, completion: @escaping (Result<Ledger, Error>) -> Void) {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 通过邮箱查找用户
        db.collection("users")
            .whereField("email", isEqualTo: normalizedEmail)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let doc = snapshot?.documents.first else {
                    completion(.failure(NSError(domain: "LedgerStore", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "未找到该邮箱的用户"])))
                    return
                }

                let memberId = doc.documentID
                guard memberId != ledger.ownerId else {
                    completion(.failure(NSError(domain: "LedgerStore", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "不能添加自己为成员"])))
                    return
                }

                guard !ledger.memberIds.contains(memberId) else {
                    completion(.failure(NSError(domain: "LedgerStore", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "该用户已在账本中"])))
                    return
                }

                var updatedLedger = ledger
                updatedLedger.memberIds.append(memberId)

                // 更新账本
                self?.updateLedger(updatedLedger) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        // 添加成员到账本列表
                        self?.db.collection("users").document(memberId)
                            .collection("myLedgers")
                            .document(ledger.id.uuidString)
                            .setData(["joinedAt": Date().timeIntervalSince1970]) { _ in
                                completion(.success(updatedLedger))
                            }
                    }
                }
            }
    }

    func removeMember(_ memberId: String, from ledger: Ledger, completion: @escaping (Result<Ledger, Error>) -> Void) {
        guard memberId != ledger.ownerId else {
            completion(.failure(NSError(domain: "LedgerStore", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "不能移除账本创建者"])))
            return
        }

        var updatedLedger = ledger
        updatedLedger.memberIds.removeAll { $0 == memberId }

        updateLedger(updatedLedger) { [weak self] error in
            if let error = error {
                completion(.failure(error))
            } else {
                self?.db.collection("users").document(memberId)
                    .collection("myLedgers")
                    .document(ledger.id.uuidString)
                    .delete { _ in
                        completion(.success(updatedLedger))
                    }
            }
        }
    }

    // MARK: - 成员信息获取

    func fetchMemberNames(ids: [String], completion: @escaping ([String: String]) -> Void) {
        guard !ids.isEmpty else {
            completion([:])
            return
        }

        var names: [String: String] = [:]
        let group = DispatchGroup()

        // 获取当前用户信息（缓存）
        if let currentUserId = userId {
            group.enter()
            db.collection("users").document(currentUserId).getDocument { snapshot, _ in
                defer { group.leave() }
                guard let data = snapshot?.data() else { return }
                let username = data["username"] as? String
                if let username = username {
                    names[currentUserId] = username
                } else if let email = data["email"] as? String {
                    names[currentUserId] = email.components(separatedBy: "@").first ?? "用户"
                }
            }
        }

        // 获取其他成员信息
        for id in ids where id != userId {
            group.enter()
            db.collection("users").document(id).getDocument { snapshot, _ in
                defer { group.leave() }
                guard let data = snapshot?.data() else { return }
                let username = data["username"] as? String
                if let username = username {
                    names[id] = username
                } else if let email = data["email"] as? String {
                    names[id] = email.components(separatedBy: "@").first ?? "用户"
                }
            }
        }

        group.notify(queue: .main) {
            completion(names)
        }
    }

    // MARK: - 数据转换

    private func ledgerFromDocument(_ doc: DocumentSnapshot, id: UUID) -> Ledger? {
        guard let data = doc.data() else { return nil }

        let title = data["title"] as? String ?? ""
        let ownerId = data["ownerId"] as? String ?? ""
        let memberIds = data["memberIds"] as? [String] ?? []
        let participants = personsFromData(data["participants"])
        let expenses = expensesFromData(data["expenses"])

        return Ledger(
            id: id,
            title: title,
            ownerId: ownerId,
            memberIds: memberIds,
            participants: participants,
            expenses: expenses
        )
    }

    private func ledgerToData(_ ledger: Ledger) -> [String: Any] {
        let data: [String: Any] = [
            "id": ledger.id.uuidString,
            "title": ledger.title,
            "ownerId": ledger.ownerId,
            "memberIds": ledger.memberIds,
            "participants": ledger.participants.map { personToData($0) },
            "expenses": ledger.expenses.map { expenseToData($0) },
            "updatedAt": Date().timeIntervalSince1970
        ]
        return data
    }

    private func personsFromData(_ value: Any?) -> [Person] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let idString = item["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = item["name"] as? String else { return nil }
            return Person(id: id, name: name)
        }
    }

    private func expensesFromData(_ value: Any?) -> [Expense] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let idString = item["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = item["title"] as? String,
                  let amountString = item["amount"] as? String,
                  let amount = Decimal(string: amountString),
                  let payerDict = item["payer"] as? [String: Any],
                  let payer = personsFromData([payerDict]).first else { return nil }

            let participants = personsFromData(item["participants"])

            return Expense(
                id: id,
                title: title,
                amount: amount,
                payer: payer,
                participants: participants
            )
        }
    }

    private func personToData(_ person: Person) -> [String: Any] {
        ["id": person.id.uuidString, "name": person.name]
    }

    private func expenseToData(_ expense: Expense) -> [String: Any] {
        [
            "id": expense.id.uuidString,
            "title": expense.title,
            "amount": "\(expense.amount)",
            "payer": personToData(expense.payer),
            "participants": expense.participants.map { personToData($0) }
        ]
    }
}
