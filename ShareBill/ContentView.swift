//
//  ContentView.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import SwiftUI
struct ContentView: View {
    @StateObject var auth = AuthManager()
    @StateObject var ledgerStore = LedgerStore()
    @StateObject var themeManager = ThemeManager()
    @State private var selectedTab = 0
    @State private var sheetType: SheetType?

    enum SheetType: Identifiable {
        case ledgerDrawer
        case addLedger
        case addExpense
        case editLedger(Ledger)
        case memberManagement(Ledger)

        var id: String {
            switch self {
            case .ledgerDrawer: return "ledgerDrawer"
            case .addLedger: return "addLedger"
            case .addExpense: return "addExpense"
            case .editLedger(let ledger): return "editLedger-\(ledger.id.uuidString)"
            case .memberManagement(let ledger): return "memberMgmt-\(ledger.id.uuidString)"
            }
        }
    }

    var body: some View {
        Group {
            if auth.user != nil {
                TabView(selection: $selectedTab) {
                    ledgerTabView
                        .tabItem {
                            Label("账本", systemImage: "book.fill")
                        }
                        .tag(0)

                    SettingsView()
                        .tabItem {
                            Label("设置", systemImage: "gearshape.fill")
                        }
                        .tag(1)
                }
                .tint(.blue)
            } else {
                LoginView()
            }
        }
        .environmentObject(auth)
        .environmentObject(ledgerStore)
        .environmentObject(themeManager)
        .preferredColorScheme(themeManager.applyTheme())
        .sheet(item: $sheetType) { item in
            switch item {
            case .ledgerDrawer:
                LedgerDrawerView(
                    showingAddLedger: { sheetType = .addLedger },
                    editingLedger: { ledger in sheetType = .editLedger(ledger) }
                )
                .environmentObject(auth)
                .environmentObject(ledgerStore)

            case .addLedger:
                AddLedgerView { newLedger in
                    if !newLedger.title.isEmpty {
                        ledgerStore.createLedger(newLedger) { error in
                            if error == nil {
                                ledgerStore.setCurrentLedger(newLedger)
                            }
                        }
                    }
                    sheetType = nil
                }

            case .addExpense:
                if let ledger = ledgerStore.currentLedger {
                    AddExpenseView(participants: ledger.participants) { newExpense in
                        if !newExpense.title.isEmpty {
                            var updatedLedger = ledger
                            updatedLedger.expenses.append(newExpense)
                            ledgerStore.updateLedger(updatedLedger)
                        }
                        sheetType = nil
                    }
                }

            case .editLedger(let ledger):
                AddLedgerView(ledger: ledger) { updated in
                    if !updated.title.isEmpty {
                        var merged = updated
                        merged.expenses = ledger.expenses
                        ledgerStore.updateLedger(merged)
                    }
                    sheetType = nil
                }

            case .memberManagement(let ledger):
                AddMemberView(ledger: ledger)
            }
        }
    }

    @ViewBuilder
    private var ledgerTabView: some View {
        NavigationStack {
            Group {
                if ledgerStore.ledgers.isEmpty {
                    emptyStateView
                } else if let ledger = ledgerStore.currentLedger {
                    ledgerDetailView(ledger)
                } else {
                    ContentUnavailableView(
                        "请选择账本",
                        systemImage: "book.closed",
                        description: Text("从左侧选择一个账本")
                    )
                }
            }
            .navigationTitle(ledgerStore.currentLedger?.title ?? "账本")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sheetType = .ledgerDrawer
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            sheetType = .addExpense
                        } label: {
                            Label("添加账单", systemImage: "plus.circle")
                        }

                        Button {
                            sheetType = .memberManagement(ledgerStore.currentLedger!)
                        } label: {
                            Label("管理成员", systemImage: "person.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("暂无账本", systemImage: "book.closed")
        } description: {
            Text("点击左上角菜单添加第一个账本")
        } actions: {
            Button {
                sheetType = .addLedger
            } label: {
                Text("添加账本")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func ledgerDetailView(_ ledger: Ledger) -> some View {
        List {
            Section("账单") {
                if ledger.expenses.isEmpty {
                    Text("暂无账单")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ForEach(ledger.expenses) { expense in
                        expenseRowView(expense)
                    }
                    .onDelete { indexSet in
                        var updated = ledger
                        for index in indexSet.sorted(by: >) {
                            updated.expenses.remove(at: index)
                        }
                        ledgerStore.updateLedger(updated)
                    }
                }
            }

            Section("分账结果") {
                let results = calculateBalanceResults(for: ledger)
                ForEach(results) { result in
                    HStack {
                        Text(result.person.name)
                        Spacer()
                        Text(result.displayText)
                            .foregroundStyle(result.isPositive ? .green : result.balance < 0 ? .red : .secondary)
                    }
                }
            }

            Section("结算方案") {
                let transfers = calculateTransfers(for: ledger)
                if transfers.isEmpty {
                    Text("账目已结清")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transfers) { transfer in
                        HStack {
                            Text("\(transfer.from.name) → \(transfer.to.name)")
                            Spacer()
                            Text(formatAmount(transfer.amount))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func expenseRowView(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(expense.title)
                    .font(.headline)
                Spacer()
                Text(formatAmount(expense.amount))
                    .font(.headline)
            }
            HStack {
                Text("\(expense.payer.name) 支付")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(expense.participants.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper Methods

    private func formatAmount(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "¥"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "¥0"
    }

    private func isZero(_ amount: Decimal) -> Bool {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        return abs(value) < 0.0001
    }

    private func calculateBalanceResults(for ledger: Ledger) -> [BalanceResult] {
        var balances: [Person: Decimal] = [:]
        for participant in ledger.participants {
            balances[participant] = 0
        }

        for expense in ledger.expenses {
            if expense.participants.isEmpty { continue }
            let share = expense.amount / Decimal(expense.participants.count)
            balances[expense.payer, default: 0] += expense.amount - share
            for participant in expense.participants where participant != expense.payer {
                balances[participant, default: 0] -= share
            }
        }

        return balances.map { BalanceResult(person: $0.key, balance: $0.value) }
            .sorted { $0.person.name < $1.person.name }
    }

    private func calculateTransfers(for ledger: Ledger) -> [Transfer] {
        let results = calculateBalanceResults(for: ledger)
        var creditors = results.filter { $0.balance > 0 }
            .map { ($0.person, $0.balance) }
            .sorted { $0.1 > $1.1 }
        var debtors = results.filter { $0.balance < 0 }
            .map { ($0.person, -$0.balance) }
            .sorted { $0.1 > $1.1 }

        var transfers: [Transfer] = []
        var i = 0
        var j = 0
        while i < debtors.count, j < creditors.count {
            let pay = min(debtors[i].1, creditors[j].1)
            if isZero(pay) { break }
            transfers.append(Transfer(from: debtors[i].0, to: creditors[j].0, amount: pay))
            debtors[i].1 -= pay
            creditors[j].1 -= pay
            if isZero(debtors[i].1) { i += 1 }
            if isZero(creditors[j].1) { j += 1 }
        }
        return transfers
    }
}

// MARK: - Supporting Types

struct BalanceResult: Identifiable {
    let id = UUID()
    let person: Person
    let balance: Decimal

    var isPositive: Bool { balance > 0 }

    var displayText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "¥"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let amountStr = formatter.string(from: NSDecimalNumber(decimal: abs(balance))) ?? "¥0"

        if balance > 0 {
            return "应收 \(amountStr)"
        } else if balance < 0 {
            return "应付 \(amountStr)"
        }
        return "已结清"
    }
}

struct Transfer: Identifiable {
    let id = UUID()
    let from: Person
    let to: Person
    let amount: Decimal
}

#Preview {
    ContentView()
}
