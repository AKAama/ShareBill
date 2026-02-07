//
//  AddExpenseView.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import SwiftUI

struct AddExpenseView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""
    @State private var amountText: String = ""
    @State private var selectedPayer: Person?
    @State private var selectedParticipants: Set<Person> = []

    let participants: [Person]
    var onSave: (Expense) -> Void
    private let existingId: UUID?

    init(expense: Expense? = nil, participants: [Person], onSave: @escaping (Expense) -> Void) {
        self.participants = participants
        self.onSave = onSave
        self.existingId = expense?.id
        _title = State(initialValue: expense?.title ?? "")
        if let amount = expense?.amount {
            _amountText = State(initialValue: formatAmountForInput(amount))
        }
        _selectedPayer = State(initialValue: expense?.payer)
        _selectedParticipants = State(initialValue: Set(expense?.participants ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账单名称") {
                    TextField("输入账单名称", text: $title)
                }

                Section("金额") {
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: amountText) { _, newValue in
                                amountText = formatAmountInput(newValue)
                            }
                    }
                }

                Section("付款人") {
                    if participants.isEmpty {
                        Text("请先在账本中添加参与者")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("选择付款人", selection: $selectedPayer) {
                            ForEach(participants) { participant in
                                Text(participant.name).tag(participant as Person?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("参与人") {
                    if participants.isEmpty {
                        Text("请先在账本中添加参与者")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(participants) { participant in
                            HStack {
                                Text(participant.name)
                                Spacer()
                                if selectedParticipants.contains(participant) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleParticipant(participant)
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingId == nil ? "新建账单" : "编辑账单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveExpense()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if selectedPayer == nil, let first = participants.first {
                    selectedPayer = first
                }
                if selectedParticipants.isEmpty, let first = participants.first {
                    selectedParticipants.insert(first)
                }
            }
        }
    }

    private var canSave: Bool {
        guard let amount = Decimal(string: amountText),
              !title.isEmpty,
              selectedPayer != nil,
              !selectedParticipants.isEmpty,
              amount > 0 else {
            return false
        }
        return true
    }

    private func toggleParticipant(_ participant: Person) {
        if selectedParticipants.contains(participant) {
            selectedParticipants.remove(participant)
        } else {
            selectedParticipants.insert(participant)
        }
    }

    private func saveExpense() {
        guard let amount = Decimal(string: amountText),
              !title.isEmpty,
              let payer = selectedPayer,
              !selectedParticipants.isEmpty else { return }

        let expense = Expense(
            id: existingId ?? UUID(),
            title: title,
            amount: amount,
            payer: payer,
            participants: Array(selectedParticipants)
        )
        onSave(expense)
        dismiss()
    }

    private func formatAmountInput(_ input: String) -> String {
        var result = input
        let allowed = CharacterSet(charactersIn: "0123456789.")
        let chars = CharacterSet(charactersIn: result)
        if !allowed.isSuperset(of: chars) {
            result = result.components(separatedBy: allowed.inverted).joined()
        }

        let parts = result.components(separatedBy: ".")
        if parts.count > 2 {
            result = parts[0] + "." + parts.dropFirst().joined()
        }
        if parts.count == 2 && parts[1].count > 2 {
            result = parts[0] + "." + String(parts[1].prefix(2))
        }
        if result.hasPrefix(".") {
            result = "0" + result
        }
        return result
    }

    private func formatAmountForInput(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? ""
    }
}

#Preview {
    AddExpenseView(participants: [
        Person(name: "张三"),
        Person(name: "李四"),
        Person(name: "王五")
    ]) { _ in }
}
