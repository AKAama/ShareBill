//
//  AuthManager.swift
//  ShareBill
//
//  Created by alex_yehui on 2025/12/14.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import Combine

class AuthManager: ObservableObject {
    @Published var user: User?
    @Published var userProfile: UserProfile?

    // Login/Register state
    @Published var loginIdentifier = ""
    @Published var loginPassword = ""
    @Published var loginError: String?
    @Published var registerError: String?
    @Published var isLoading = false

    private var handle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()

    init() {
        self.user = Auth.auth().currentUser
        listenToAuthState()
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private func listenToAuthState() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            DispatchQueue.main.async {
                self?.user = firebaseUser
                if let uid = firebaseUser?.uid {
                    self?.fetchUserProfile(uid: uid)
                } else {
                    self?.userProfile = nil
                }
            }
        }
    }

    private func fetchUserProfile(uid: String) {
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if let data = snapshot?.data() {
                let base64Avatar = data["avatarBase64"] as? String
                DispatchQueue.main.async {
                    self.userProfile = UserProfile(
                        uid: uid,
                        username: data["username"] as? String,
                        email: data["email"] as? String,
                        phone: data["phone"] as? String,
                        avatarBase64: base64Avatar
                    )
                }
            }
        }
    }

    // 登录 - 支持邮箱、手机号、用户名
    func signIn(identifier: String, password: String, completion: @escaping (Error?) -> Void) {
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if isValidEmail(identifier) {
            Auth.auth().signIn(withEmail: identifier, password: password) { [weak self] result, error in
                DispatchQueue.main.async {
                    self?.user = result?.user
                    completion(error)
                }
            }
        } else if isValidPhone(identifier) {
            // 手机号登录需要先查询对应的邮箱
            findEmailByPhone(phone: identifier) { [weak self] email, error in
                if let email = email {
                    Auth.auth().signIn(withEmail: email, password: password) { result, error in
                        DispatchQueue.main.async {
                            self?.user = result?.user
                            completion(error)
                        }
                    }
                } else {
                    completion(error ?? NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到该手机号绑定的账户"]))
                }
            }
        } else {
            // 用户名登录
            findEmailByUsername(username: identifier) { [weak self] email, error in
                if let email = email {
                    Auth.auth().signIn(withEmail: email, password: password) { result, error in
                        DispatchQueue.main.async {
                            self?.user = result?.user
                            completion(error)
                        }
                    }
                } else {
                    completion(error ?? NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户名不存在"]))
                }
            }
        }
    }

    // 注册
    func signUp(
        username: String,
        email: String,
        phone: String,
        password: String,
        completion: @escaping (Error?) -> Void
    ) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }

            if let error = error {
                completion(error)
                return
            }

            guard let uid = result?.user.uid else {
                completion(NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "创建账户失败"]))
                return
            }

            // 保存用户信息到 Firestore
            let userData: [String: Any] = [
                "username": username.lowercased(),
                "email": email.lowercased(),
                "phone": phone,
                "createdAt": Date().timeIntervalSince1970
            ]

            self.db.collection("users").document(uid).setData(userData) { firestoreError in
                DispatchQueue.main.async {
                    if let firestoreError = firestoreError {
                        completion(firestoreError)
                    } else {
                        self.user = result?.user
                        self.fetchUserProfile(uid: uid)
                        completion(nil)
                    }
                }
            }
        }
    }

    // 检查用户名是否已存在
    func checkUsernameExists(_ username: String, completion: @escaping (Bool) -> Void) {
        let lowercaseUsername = username.lowercased()
        db.collection("users")
            .whereField("username", isEqualTo: lowercaseUsername)
            .getDocuments { snapshot, _ in
                completion(snapshot?.documents.isEmpty == false)
            }
    }

    // 根据手机号查找邮箱
    private func findEmailByPhone(phone: String, completion: @escaping (String?, Error?) -> Void) {
        db.collection("users")
            .whereField("phone", isEqualTo: phone)
            .getDocuments { snapshot, error in
                if let doc = snapshot?.documents.first {
                    completion(doc.data()["email"] as? String, nil)
                } else {
                    completion(nil, error)
                }
            }
    }

    // 根据用户名查找邮箱
    private func findEmailByUsername(username: String, completion: @escaping (String?, Error?) -> Void) {
        db.collection("users")
            .whereField("username", isEqualTo: username.lowercased())
            .getDocuments { snapshot, error in
                if let doc = snapshot?.documents.first {
                    completion(doc.data()["email"] as? String, nil)
                } else {
                    completion(nil, error)
                }
            }
    }

    // 验证用户名格式
    func isValidUsername(_ username: String) -> Bool {
        let pattern = "^[a-zA-Z][a-zA-Z0-9_]*$"
        return username.range(of: pattern, options: .regularExpression) != nil && username.count >= 3
    }

    // 验证手机号格式
    func isValidPhone(_ phone: String) -> Bool {
        let pattern = "^1[3-9]\\d{9}$"
        return phone.range(of: pattern, options: .regularExpression) != nil
    }

    // 验证邮箱格式
    func isValidEmail(_ email: String) -> Bool {
        let pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // 更新用户头像 (base64)
    func updateAvatar(_ imageData: Data, completion: @escaping (Error?) -> Void) {
        guard let uid = user?.uid else {
            completion(NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未登录"]))
            return
        }

        let base64String = imageData.base64EncodedString()
        db.collection("users").document(uid).updateData(["avatarBase64": base64String]) { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.fetchUserProfile(uid: uid)
                }
                completion(error)
            }
        }
    }

    // 更新用户名
    func updateUsername(_ username: String, completion: @escaping (Error?) -> Void) {
        guard let uid = user?.uid else {
            completion(NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未登录"]))
            return
        }

        db.collection("users").document(uid).updateData(["username": username.lowercased()]) { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.fetchUserProfile(uid: uid)
                }
                completion(error)
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            self.user = nil
            self.userProfile = nil
        } catch {
            print("Sign out failed: \(error)")
        }
    }

    func resetPassword(email: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }

    func reauthenticate(email: String, password: String, completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"]))
            return
        }

        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        user.reauthenticate(with: credential) { _, error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }

    func deleteAccount(completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"]))
            return
        }

        user.delete { error in
            DispatchQueue.main.async {
                if error == nil {
                    self.user = nil
                    self.userProfile = nil
                }
                completion(error)
            }
        }
    }
}

// MARK: - User Profile Model

struct UserProfile {
    let uid: String
    let username: String?
    let email: String?
    let phone: String?
    let avatarBase64: String?

    var displayName: String {
        username ?? email?.components(separatedBy: "@").first ?? "用户"
    }

    var avatarImage: UIImage? {
        guard let base64 = avatarBase64,
              let data = Data(base64Encoded: base64) else {
            return nil
        }
        return UIImage(data: data)
    }
}
