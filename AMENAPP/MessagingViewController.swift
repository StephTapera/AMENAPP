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
    
    private func uploadImage(_ image: UIImage, completion: @escaping (String?) -> Void) {
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            print("❌ Failed to compress image")
            completion(nil)
            return
        }
        
        // Create unique filename
        let filename = "\(UUID().uuidString).jpg"
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("messages/\(conversationId ?? "unknown")/\(filename)")
        
        print("📤 Uploading image to Firebase Storage...")
        
        // Upload with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        imageRef.putData(imageData, metadata: metadata) { [weak self] metadata, error in
            if let error = error {
                print("❌ Upload failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            print("✅ Image uploaded successfully")
            
            // Get download URL
            imageRef.downloadURL { url, error in
                if let error = error {
                    print("❌ Failed to get download URL: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let downloadURL = url?.absoluteString else {
                    print("❌ Download URL is nil")
                    completion(nil)
                    return
                }
                
                print("✅ Download URL obtained: \(downloadURL)")
                completion(downloadURL)
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
        
        // Upload image
        uploadImage(image) { [weak self] photoURL in
            guard let self = self, let url = photoURL else {
                return
            }
            
            // Send photo message
            self.rtdb.sendPhotoMessage(conversationId: self.conversationId, photoURL: url) { success in
                if !success {
                    self.showError("Failed to send photo")
                }
            }
        }
    }
}
