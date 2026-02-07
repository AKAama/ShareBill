import Foundation

class DataPersistence {
    
    private static let ledgersKey = "ShareBill.ledgers"
    
    static func saveLedgers(_ ledgers: [Ledger]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(ledgers)
            UserDefaults.standard.set(data, forKey: ledgersKey)
        } catch {
            print("保存账本数据失败: \(error)")
        }
    }
    
    static func loadLedgers() -> [Ledger] {
        guard let data = UserDefaults.standard.data(forKey: ledgersKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let ledgers = try decoder.decode([Ledger].self, from: data)
            return ledgers
        } catch {
            print("加载账本数据失败: \(error)")
            return []
        }
    }
    
    static func addLedger(_ ledger: Ledger) {
        var ledgers = loadLedgers()
        ledgers.append(ledger)
        saveLedgers(ledgers)
    }
    
    static func updateLedger(_ updatedLedger: Ledger) {
        var ledgers = loadLedgers()
        if let index = ledgers.firstIndex(where: { $0.id == updatedLedger.id }) {
            ledgers[index] = updatedLedger
            saveLedgers(ledgers)
        }
    }
    
    static func deleteLedger(_ ledgerId: UUID) {
        var ledgers = loadLedgers()
        ledgers.removeAll { $0.id == ledgerId }
        saveLedgers(ledgers)
    }
}
