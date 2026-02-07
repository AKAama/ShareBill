import Foundation

// 清理UserDefaults中的账本数据
func cleanUserDefaults() {
    let ledgersKey = "ShareBill.ledgers"
    
    // 检查是否存在账本数据
    if UserDefaults.standard.object(forKey: ledgersKey) != nil {
        print("发现测试数据，正在清理...")
        UserDefaults.standard.removeObject(forKey: ledgersKey)
        UserDefaults.standard.synchronize()
        print("UserDefaults数据已清理")
    } else {
        print("UserDefaults中没有账本数据")
    }
}

// 执行清理
cleanUserDefaults()
