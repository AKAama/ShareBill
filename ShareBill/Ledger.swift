//
//  Ledger.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//
import Foundation

struct Person: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

extension Person: Comparable {
    static func < (lhs: Person, rhs: Person) -> Bool {
        return lhs.name < rhs.name
    }
}

extension Person: Equatable {
    static func == (lhs: Person, rhs: Person) -> Bool {
        return lhs.id == rhs.id
    }
}

struct Ledger: Identifiable, Codable {
    let id: UUID
    var title: String
    var participants: [Person]
    var expenses: [Expense]
    
    init(id: UUID = UUID(), title: String, participants: [Person] = [], expenses: [Expense] = []) {
        self.id = id
        self.title = title
        self.participants = participants
        self.expenses = expenses
    }
}
