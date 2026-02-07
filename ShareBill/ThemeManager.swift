//
//  ThemeManager.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import Foundation
import SwiftUI
import Combine

enum AppTheme: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme {
        didSet {
            saveTheme()
        }
    }

    private let userDefaultsKey = "SelectedTheme"

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
           let theme = AppTheme(rawValue: rawValue) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .system
        }
    }

    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.rawValue, forKey: userDefaultsKey)
    }

    func applyTheme() -> ColorScheme? {
        return currentTheme.colorScheme
    }
}
