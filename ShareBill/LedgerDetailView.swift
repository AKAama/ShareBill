//
//  LedgerDetailView.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import SwiftUI

struct LedgerDetailView: View {
    
    let ledgerId: UUID
    @EnvironmentObject var store: LedgerStore
    @State private var showingAddExpense = false
    @State private var showingEditExpense = false
    @State private var editingExpense: Expense?
    
    struct BalanceResult: Identifiable {
        let id = UUID()
        let person: Person
        let balance: Decimal // 正数表示需要收取的金额，负数表示需要支付的金额
        
        var isPositive: Bool {
            return balance > 0
        }
        
        var displayText: String {
            if balance > 0 {
                return "应收: \(formatAmount(balance))"
            } else if balance < 0 {
                return "应付: \(formatAmount(abs(balance)))"
            } else {
                return "收支平衡"
            }
        }
    }
    
    var balanceResults: [BalanceResult] {
        guard let ledger = ledger else { return [] }
        var balances: [Person: Decimal] = [:]
        
        // 初始化每个人的余额为0
        for participant in ledger.participants {
            balances[participant] = 0
        }
        
        // 计算每笔支出的分账
        for expense in ledger.expenses {
            if expense.participants.isEmpty {
                continue
            }
            
            let share = expense.amount / Decimal(expense.participants.count)
            
            // 付款人应收取的金额 = 总金额 - 自己的份额
            balances[expense.payer, default: 0] += expense.amount - share
            
            // 其他参与人应支付的金额 = 份额
            for participant in expense.participants {
                if participant != expense.payer {
                    balances[participant, default: 0] -= share
                }
            }
        }
        
        // 转换为BalanceResult数组并排序
        return balances.map { BalanceResult(person: $0.key, balance: $0.value) }
            .sorted { $0.person.name < $1.person.name }
    }

    struct Transfer: Identifiable {
        let id = UUID()
        let from: Person
        let to: Person
        let amount: Decimal
    }
    
    var transfers: [Transfer] {
        let results = balanceResults
        var creditors: [(Person, Decimal)] = results
            .filter { $0.balance > 0 }
            .map { ($0.person, $0.balance) }
            .sorted { $0.1 > $1.1 }
        var debtors: [(Person, Decimal)] = results
            .filter { $0.balance < 0 }
            .map { ($0.person, -$0.balance) } // 转为正数欠款
            .sorted { $0.1 > $1.1 }
        
        var output: [Transfer] = []
        var i = 0
        var j = 0
        while i < debtors.count, j < creditors.count {
            let pay = min(debtors[i].1, creditors[j].1)
            if isZero(pay) { break }
            output.append(Transfer(from: debtors[i].0, to: creditors[j].0, amount: pay))
            
            debtors[i].1 -= pay
            creditors[j].1 -= pay
            
            if isZero(debtors[i].1) { i += 1 }
            if isZero(creditors[j].1) { j += 1 }
        }
        return output
    }
    
    private var ledger: Ledger? {
        store.ledgers.first(where: { $0.id == ledgerId })
    }

    var body: some View {
        Group {
            if let ledger = ledger {
                List {
                    Section(header: Text("账单")) {
                        ForEach(ledger.expenses) { expense in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(expense.title)
                                        .font(.headline)
                                    Spacer()
                                    Text(formatAmount(expense.amount))
                                        .font(.headline)
                                }
                                HStack {
                                    Text("付款人: \(expense.payer.name)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                HStack {
                                    Text("参与人: \(expense.participants.map { $0.name }.joined(separator: ", "))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                Divider()
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) {
                                    var updated = ledger
                                    updated.expenses.removeAll { $0.id == expense.id }
                                    store.updateLedger(updated)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button("编辑") {
                                    editingExpense = expense
                                    showingEditExpense = true
                                }
                                .tint(.blue)
                            }
                        }
                        
                        if ledger.expenses.isEmpty {
                            Text("暂无账单记录")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        }
                    }
                    
                    Section(header: Text("分账结果")) {
                        ForEach(balanceResults) { result in
                            HStack {
                                Text(result.person.name)
                                    .font(.headline)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(result.displayText)
                                        .font(.subheadline)
                                        .foregroundColor(result.isPositive ? .green : result.balance < 0 ? .red : .secondary)
                                    Text(formatAmount(result.balance))
                                        .font(.headline)
                                        .foregroundColor(result.isPositive ? .green : result.balance < 0 ? .red : .secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Section(header: Text("结算转账方案")) {
                        if transfers.isEmpty {
                            Text("暂无需要结算的转账")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(transfers) { transfer in
                                HStack {
                                    Text("\(transfer.from.name) → \(transfer.to.name)")
                                    Spacer()
                                    Text(formatAmount(transfer.amount))
                                        .font(.headline)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .navigationTitle(ledger.title)
            } else {
                Text("账本不存在")
                    .foregroundColor(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddExpense = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            if let ledger = ledger {
                AddExpenseView(participants: ledger.participants) { newExpense in
                if !newExpense.title.isEmpty {
                    var updatedLedger = ledger
                    updatedLedger.expenses.append(newExpense)
                    store.updateLedger(updatedLedger)
                }
                showingAddExpense = false
            }
            }
        }
        .sheet(isPresented: $showingEditExpense) {
            if let ledger = ledger, let expense = editingExpense {
                AddExpenseView(expense: expense, participants: ledger.participants) { updatedExpense in
                    if !updatedExpense.title.isEmpty {
                        var updatedLedger = ledger
                        if let index = updatedLedger.expenses.firstIndex(where: { $0.id == updatedExpense.id }) {
                            updatedLedger.expenses[index] = updatedExpense
                            store.updateLedger(updatedLedger)
                        }
                    }
                    showingEditExpense = false
                    editingExpense = nil
                }
            }
        }
    }
}

func formatAmount(_ amount: Decimal) -> String {
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
