//
//  MessagingViewController.swift
//  AMEN App
//
//  Example of instant messaging with Realtime Database
//

import UIKit
import FirebaseAuth
import FirebaseStorage

class MessagingViewController: UIViewController {
    
    // MARK: - Properties
    
    var conversationId: String!
    /// UID of the other participant — set by the presenter before pushing/presenting this VC.
    /// Required so MediaSafetyGateway can check minor status before any image upload.
    var recipientUserId: String = ""
    /// Injectable safety gateway — defaults to the real singleton; swap in tests.
    var mediaSafetyGateway: any MediaSafetyEvaluating = MediaSafetyGateway.shared
    private let rtdb = RealtimeDatabaseManager.shared
    private var messagesObserverKey: String?
    private var messages: [[String: Any]] = []
    
    // MARK: - UI Elements
    
    @IBOutlet weak var messagesTableView: UITableView!
    @IBOutlet weak var messageTextField: UITextField!
    @IBOutlet weak var sendButton: UIButton!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Verify user is authenticated
        guard Auth.auth().currentUser != nil else {
            showError("You must be logged in to view messages")
            return
        }
        
        setupUI()
        observeMessages()
        resetUnreadCount()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeObserver()
    }
    
    deinit {
        removeObserver()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        messagesTableView.delegate = self
        messagesTableView.dataSource = self
        messagesTableView.transform = CGAffineTransform(scaleX: 1, y: -1)
    }
    
    private func observeMessages() {
        messagesObserverKey = rtdb.observeMessages(conversationId: conversationId) { [weak self] message in
            self?.messages.insert(message, at: 0)
            self?.messagesTableView.reloadData()
            
            // Scroll to bottom
            if let count = self?.messages.count, count > 0 {
                let indexPath = IndexPath(row: 0, section: 0)
                self?.messagesTableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
            }
        }
    }
    
    private func resetUnreadCount() {
        // Reset unread messages when viewing conversation
        rtdb.resetUnreadMessages()
    }
    
    private func removeObserver() {
        if let key = messagesObserverKey {
            rtdb.removeObserver(key: key)
            messagesObserverKey = nil
        }
    }
    
    // MARK: - Actions
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        guard let text = messageTextField.text, !text.isEmpty else {
            return
        }
        
        // Send message instantly!
        rtdb.sendMessage(conversationId: conversationId, text: text) { [weak self] success in
            if success {
                self?.messageTextField.text = ""
                // Message will appear automatically via observer!
            } else {
                self?.showError("Failed to send message")
            }
        }
    }
    
    @IBAction func attachPhotoButtonTapped(_ sender: UIButton) {
        // Show image picker
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        present(picker, animated: true)
    }
    
    // MARK: - Helper Methods
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func uploadImage(_ image: UIImage) async -> String? {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            dlog("❌ No authenticated user for image upload")
            await MainActor.run { showError("You must be logged in to send photos") }
            return nil
        }

        // ── MEDIA SAFETY GATEWAY ────────────────────────────────────────────────
        // Evaluate BEFORE any data leaves the device.
        // Decision: allow / allowWithAsyncScan → proceed.
        // hold / reject / freeze → abort immediately, show user-facing error.
        // ────────────────────────────────────────────────────────────────────────
        let messageId = UUID().uuidString
        let safetyDecision = await mediaSafetyGateway.evaluate(
            image: image,
            senderId: currentUserId,
            recipientId: recipientUserId,
            conversationId: conversationId ?? "unknown",
            messageId: messageId
        )

        switch safetyDecision {
        case .reject(let reason), .freeze(let reason):
            dlog("🛑 [MediaSafety] Upload blocked — \(reason)")
            await MainActor.run { showError("This photo cannot be sent. Please review our community guidelines.") }
            return nil
        case .hold(let reason):
            dlog("⏸️ [MediaSafety] Upload held — \(reason)")
            await MainActor.run { showError("This photo is under review and cannot be sent at this time.") }
            return nil
        case .allow, .allowWithAsyncScan:
            break  // Proceed with upload
        }
        // ────────────────────────────────────────────────────────────────────────

        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            dlog("❌ Failed to compress image")
            return nil
        }

        // Create unique filename
        let filename = "\(messageId).jpg"
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("messages/\(conversationId ?? "unknown")/\(filename)")

        dlog("📤 Uploading image to Firebase Storage...")

        // Upload with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        return await withCheckedContinuation { continuation in
            imageRef.putData(imageData, metadata: metadata) { _, error in
                if let error = error {
                    dlog("❌ Upload failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                dlog("✅ Image uploaded successfully")

                imageRef.downloadURL { url, error in
                    if let error = error {
                        dlog("❌ Failed to get download URL: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                        return
                    }

                    guard let downloadURL = url?.absoluteString else {
                        dlog("❌ Download URL is nil")
                        continuation.resume(returning: nil)
                        return
                    }

                    dlog("✅ Download URL obtained: \(downloadURL)")
                    continuation.resume(returning: downloadURL)
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension MessagingViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        let senderId = message["senderId"] as? String
        let isMe = senderId == Auth.auth().currentUser?.uid
        
        let cell = tableView.dequeueReusableCell(
            withIdentifier: isMe ? "MyMessageCell" : "TheirMessageCell",
            for: indexPath
        )
        
        cell.transform = CGAffineTransform(scaleX: 1, y: -1)
        
        if let text = message["text"] as? String {
            cell.textLabel?.text = text
        } else if message["photoURL"] != nil {
            cell.textLabel?.text = "📷 Photo"
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension MessagingViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension MessagingViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        guard let image = info[.originalImage] as? UIImage else {
            return
        }

        // Upload image — safety gateway runs inside uploadImage before any putData call
        Task { [weak self] in
            guard let self else { return }
            guard let photoURL = await self.uploadImage(image) else {
                return  // uploadImage already showed an error to the user
            }

            // Send photo message
            self.rtdb.sendPhotoMessage(conversationId: self.conversationId, photoURL: photoURL) { [weak self] success in
                if !success {
                    self?.showError("Failed to send photo")
                }
            }
        }
    }
}
