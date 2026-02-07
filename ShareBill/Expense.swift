//
//  Expense.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import Foundation

struct Expense: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Decimal
    var payer: Person
    var participants: [Person]
    
    init(id: UUID = UUID(), title: String, amount: Decimal, payer: Person, participants: [Person]) {
        self.id = id
        self.title = title
        self.amount = amount
        self.payer = payer
        self.participants = participants
    }
}
