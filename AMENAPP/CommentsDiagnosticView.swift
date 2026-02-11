//
//  CommentsDiagnosticView.swift
//  AMENAPP
//
//  Diagnostic view to test comment reading from Firebase RTDB
//

import SwiftUI
import FirebaseDatabase
import FirebaseAuth

struct CommentsDiagnosticView: View {
    @State private var postId: String = ""
    @State private var diagnosticOutput: String = "Enter a post ID and tap 'Run Diagnostic'"
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Comments Diagnostic Tool")
                    .font(.custom("OpenSans-Bold", size: 24))

                Text("This tool helps diagnose why comments aren't loading")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.6))

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Post ID:")
                        .font(.custom("OpenSans-SemiBold", size: 16))

                    TextField("Enter post ID", text: $postId)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                }

                Button {
                    runDiagnostic()
                } label: {
                    if isRunning {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Run Diagnostic")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(postId.isEmpty || isRunning)

                Divider()

                Text("Diagnostic Output:")
                    .font(.custom("OpenSans-SemiBold", size: 16))

                ScrollView {
                    Text(diagnosticOutput)
                        .font(.custom("Menlo", size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.black)
                        .foregroundStyle(.green)
                        .cornerRadius(8)
                }
                .frame(height: 400)
            }
            .padding()
        }
    }

    private func runDiagnostic() {
        isRunning = true
        diagnosticOutput = "🔍 Running diagnostic...\n\n"

        Task {
            await performDiagnostic()
            await MainActor.run {
                isRunning = false
            }
        }
    }

    private func performDiagnostic() async {
        var output = ""

        // Step 1: Check authentication
        output += "━━━ STEP 1: Authentication ━━━\n"
        guard let currentUser = Auth.auth().currentUser else {
            output += "❌ NOT AUTHENTICATED\n"
            output += "You must be logged in to read comments\n\n"
            await updateOutput(output)
            return
        }
        output += "✅ Authenticated as: \(currentUser.uid)\n"
        output += "   Email: \(currentUser.email ?? "none")\n\n"

        // Step 2: Check database configuration
        output += "━━━ STEP 2: Database Configuration ━━━\n"
        let databaseURL = "https://amen-5e359-default-rtdb.firebaseio.com"
        let database = Database.database(url: databaseURL)
        output += "✅ Database URL: \(databaseURL)\n"
        output += "   Using correct instance: YES\n\n"
        await updateOutput(output)

        // Step 3: Test connection
        output += "━━━ STEP 3: Connection Test ━━━\n"
        let connectedRef = database.reference(withPath: ".info/connected")

        do {
            let snapshot = try await connectedRef.getData()
            if let connected = snapshot.value as? Bool {
                if connected {
                    output += "✅ CONNECTED to Firebase RTDB\n\n"
                } else {
                    output += "❌ DISCONNECTED from Firebase RTDB\n\n"
                }
            }
        } catch {
            output += "⚠️ Could not check connection: \(error)\n\n"
        }
        await updateOutput(output)

        // Step 4: Try to read comments
        output += "━━━ STEP 4: Reading Comments ━━━\n"
        output += "Path: postInteractions/\(postId)/comments\n\n"

        let ref = database.reference()
        let commentsRef = ref.child("postInteractions").child(postId).child("comments")

        await updateOutput(output)

        do {
            let snapshot = try await commentsRef.getData()

            output += "📊 Query Result:\n"
            output += "   Snapshot exists: \(snapshot.exists())\n"
            output += "   Has children: \(snapshot.hasChildren())\n"
            output += "   Children count: \(snapshot.childrenCount)\n\n"

            if snapshot.exists() {
                output += "✅ DATA FOUND!\n\n"

                // Get raw value
                if let rawValue = snapshot.value {
                    output += "Raw value type: \(type(of: rawValue))\n\n"

                    if let dict = rawValue as? [String: Any] {
                        output += "Found \(dict.count) comments:\n\n"

                        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                            output += "━━━ Comment: \(key) ━━━\n"

                            if let commentData = value as? [String: Any] {
                                output += "  Fields:\n"
                                for (field, fieldValue) in commentData.sorted(by: { $0.key < $1.key }) {
                                    output += "    • \(field): \(fieldValue)\n"
                                }
                            }
                            output += "\n"
                        }
                    }
                }
            } else {
                output += "❌ NO DATA FOUND\n\n"
                output += "Possible reasons:\n"
                output += "1. No comments exist for this post\n"
                output += "2. Post ID is incorrect\n"
                output += "3. Security rules blocking read\n\n"

                // Test reading the parent path
                output += "Testing parent path...\n"
                let postRef = ref.child("postInteractions").child(postId)
                let postSnapshot = try await postRef.getData()

                output += "Parent exists: \(postSnapshot.exists())\n"
                if postSnapshot.exists() {
                    output += "Parent has children: \(postSnapshot.hasChildren())\n"
                    output += "Parent children: \(postSnapshot.childrenCount)\n"

                    if let dict = postSnapshot.value as? [String: Any] {
                        output += "Parent keys: \(dict.keys.joined(separator: ", "))\n"
                    }
                }
                output += "\n"
            }

        } catch {
            output += "❌ ERROR reading comments:\n"
            output += "   \(error.localizedDescription)\n\n"

            if let nsError = error as NSError? {
                output += "Error details:\n"
                output += "   Domain: \(nsError.domain)\n"
                output += "   Code: \(nsError.code)\n"
                output += "   Info: \(nsError.userInfo)\n\n"
            }

            output += "Possible causes:\n"
            output += "1. Security rules blocking read access\n"
            output += "2. Network error\n"
            output += "3. Invalid post ID\n\n"
        }

        await updateOutput(output)

        // Step 5: Check security rules
        output += "━━━ STEP 5: Expected Security Rules ━━━\n"
        output += "At path: postInteractions/$postId\n"
        output += "Should have: .read = 'auth != null'\n\n"
        output += "Current user authenticated: ✅ YES\n"
        output += "Should have read access: ✅ YES\n\n"

        output += "━━━ DIAGNOSTIC COMPLETE ━━━\n"
        await updateOutput(output)
    }

    @MainActor
    private func updateOutput(_ text: String) {
        diagnosticOutput = text
    }
}

#Preview {
    CommentsDiagnosticView()
}
