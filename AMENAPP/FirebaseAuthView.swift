//
//  FirebaseAuthView.swift
//  AMENAPP
//
//  Simple Authentication View for Testing
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FirebaseAuthView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var errorMessage = ""
    @State private var isAuthenticated = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo or App Name
                VStack(spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.primary)
                    
                    Text("AMENAPP")
                        .font(.custom("OpenSans-Bold", size: 32))
                    
                    Text("Connect with your faith community")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Sign Up Fields
                if isSignUp {
                    VStack(spacing: 16) {
                        TextField("Display Name", text: $displayName)
                            .textContentType(.name)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                    }
                }
                
                // Email & Password Fields
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                    
                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                }
                
                // Error Message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Sign In/Up Button
                Button {
                    if isSignUp {
                        signUp()
                    } else {
                        signIn()
                    }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary)
                    )
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty || (isSignUp && displayName.isEmpty))
                
                // Toggle Sign In/Up
                Button {
                    withAnimation {
                        isSignUp.toggle()
                        errorMessage = ""
                    }
                } label: {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                }
                .padding(.top, 8)
                
                // OR Divider
                HStack {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                    
                    Text("OR")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                }
                .padding(.vertical, 16)
                
                // Anonymous Sign In (for testing)
                Button {
                    signInAnonymously()
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text("Continue as Guest")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1.5)
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $isAuthenticated) {
            // Navigate to main app
            ContentView()
        }
        .onAppear {
            checkAuthStatus()
        }
    }
    
    // MARK: - Authentication Methods
    
    private func checkAuthStatus() {
        if Auth.auth().currentUser != nil {
            isAuthenticated = true
        }
    }
    
    private func signIn() {
        isLoading = true
        errorMessage = ""
        
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            isLoading = false
            
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            
            isAuthenticated = true
        }
    }
    
    private func signUp() {
        isLoading = true
        errorMessage = ""
        
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                isLoading = false
                errorMessage = error.localizedDescription
                return
            }
            
            // Update display name
            let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
            changeRequest?.displayName = displayName
            changeRequest?.commitChanges { error in
                isLoading = false
                
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                
                // Create user document in Firestore
                createUserDocument()
                
                isAuthenticated = true
            }
        }
    }
    
    private func signInAnonymously() {
        isLoading = true
        errorMessage = ""
        
        Auth.auth().signInAnonymously { result, error in
            isLoading = false
            
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            
            print("✅ Signed in anonymously with UID: \(result?.user.uid ?? "")")
            isAuthenticated = true
        }
    }
    
    private func createUserDocument() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        
        // Create name keywords for search
        let nameComponents = displayName.lowercased().split(separator: " ")
        let keywords = nameComponents.map { String($0) }
        
        let userData: [String: Any] = [
            "name": displayName,
            "email": email,
            "avatarUrl": NSNull(),
            "isOnline": true,
            "nameKeywords": keywords,
            "createdAt": Timestamp(date: Date())
        ]
        
        userRef.setData(userData) { error in
            if let error = error {
                print("Error creating user document: \(error)")
            } else {
                print("✅ User document created")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FirebaseAuthView()
}
