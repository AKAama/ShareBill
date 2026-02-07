import Foundation
import Combine
import FirebaseFirestore

final class LedgerStore: ObservableObject {
    @Published private(set) var ledgers: [Ledger] = []
    @Published var currentLedger: Ledger?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var userId: String?
    private let userDefaultsKey = "CurrentLedgerId"

    func setCurrentLedger(_ ledger: Ledger) {
        currentLedger = ledger
        UserDefaults.standard.set(ledger.id.uuidString, forKey: userDefaultsKey)
    }

    private func loadCurrentLedger() {
        guard let ledgerId = UserDefaults.standard.string(forKey: userDefaultsKey),
              let uuid = UUID(uuidString: ledgerId),
              let ledger = ledgers.first(where: { $0.id == uuid }) else {
            currentLedger = ledgers.first
            return
        }
        currentLedger = ledger
    }

    func bind(userId: String) {
        if self.userId == userId, listener != nil {
            return
        }

        self.userId = userId
        listener?.remove()

        let ref = db
            .collection("users")
            .document(userId)
            .collection("ledgers")

        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                print("Ledger listener error: \(error)")
                return
            }

            guard let snapshot else { return }

            self.ledgers = snapshot.documents.compactMap { doc in
                self.ledgerFromDocument(doc)
            }
            .sorted { $0.title < $1.title }
            self.loadCurrentLedger()
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        userId = nil
        ledgers = []
    }

    func addLedger(_ ledger: Ledger) {
        upsertRemote(ledger)
        upsertLocal(ledger)
    }

    func updateLedger(_ ledger: Ledger) {
        upsertRemote(ledger)
        upsertLocal(ledger)
    }

    func deleteLedger(_ ledger: Ledger) {
        guard let userId else { return }

        db.collection("users")
            .document(userId)
            .collection("ledgers")
            .document(ledger.id.uuidString)
            .delete()

        ledgers.removeAll { $0.id == ledger.id }

        // 如果删除的是当前账本，切换到另一个账本
        if currentLedger?.id == ledger.id {
            currentLedger = ledgers.first
            if let firstLedger = currentLedger {
                UserDefaults.standard.set(firstLedger.id.uuidString, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }

    private func upsertRemote(_ ledger: Ledger) {
        guard let userId else { return }

        db.collection("users")
            .document(userId)
            .collection("ledgers")
            .document(ledger.id.uuidString)
            .setData(ledgerToData(ledger), merge: true)
    }

    private func upsertLocal(_ ledger: Ledger) {
        if let index = ledgers.firstIndex(where: { $0.id == ledger.id }) {
            ledgers[index] = ledger
        } else {
            ledgers.append(ledger)
        }
        ledgers.sort { $0.title < $1.title }

        // 同时更新当前账本
        if currentLedger?.id == ledger.id {
            currentLedger = ledger
        }
    }

    private func ledgerFromDocument(_ doc: QueryDocumentSnapshot) -> Ledger? {
        let data = doc.data()
        let idString = (data["id"] as? String) ?? doc.documentID
        guard let id = UUID(uuidString: idString) else { return nil }
        let title = data["title"] as? String ?? ""
        let participants = personsFromData(data["participants"])
        let expenses = expensesFromData(data["expenses"])
        return Ledger(id: id, title: title, participants: participants, expenses: expenses)
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
                  let payerDict = item["payer"] as? [String: Any] else { return nil }

            let payer = personsFromData([payerDict]).first
            let participants = personsFromData(item["participants"])
            guard let payer else { return nil }

            return Expense(id: id, title: title, amount: amount, payer: payer, participants: participants)
        }
    }

    private func ledgerToData(_ ledger: Ledger) -> [String: Any] {
        [
            "id": ledger.id.uuidString,
            "title": ledger.title,
            "participants": ledger.participants.map { personToData($0) },
            "expenses": ledger.expenses.map { expenseToData($0) }
        ]
    }

    private func personToData(_ person: Person) -> [String: Any] {
        [
            "id": person.id.uuidString,
            "name": person.name
        ]
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
