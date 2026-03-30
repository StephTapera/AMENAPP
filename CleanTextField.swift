//
//  CleanTextField.swift
//  AMENAPP
//
//  Created by Steph on 2/1/26.
//
//  Reusable clean text field component with optional secure entry
//

import SwiftUI

struct ReusableCleanTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var showPasswordToggle: Bool = false
    @Binding var showPassword: Bool
    
    @FocusState private var isFocused: Bool
    
    init(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        showPasswordToggle: Bool = false,
        showPassword: Binding<Bool> = .constant(false)
    ) {
        self.icon = icon
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.showPasswordToggle = showPasswordToggle
        self._showPassword = showPassword
    }
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isFocused ? Color.purple : Color.gray.opacity(0.6))
                .frame(width: 24)
            
            if isSecure && !showPassword {
                SecureField(placeholder, text: $text)
                    .font(.system(size: 16))
                    .keyboardType(keyboardType)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: $text)
                    .font(.system(size: 16))
                    .keyboardType(keyboardType)
                    .focused($isFocused)
                    .textInputAutocapitalization(isSecure ? .never : .words)
                    .autocorrectionDisabled()
            }
            
            if showPasswordToggle && !text.isEmpty {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.gray.opacity(0.6))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isFocused ? Color.purple.opacity(0.4) : Color.clear,
                    lineWidth: 2
                )
        )
    }
}

// MARK: - Simple variant without password toggle

struct SimpleCleanTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isFocused ? Color.purple : Color.gray.opacity(0.6))
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .keyboardType(keyboardType)
                .focused($isFocused)
                .autocorrectionDisabled()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isFocused ? Color.purple.opacity(0.4) : Color.clear,
                    lineWidth: 2
                )
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ReusableCleanTextField(
            icon: "envelope.fill",
            placeholder: "Email",
            text: .constant("")
        )
        
        ReusableCleanTextField(
            icon: "lock.fill",
            placeholder: "Password",
            text: .constant(""),
            isSecure: true,
            showPasswordToggle: true,
            showPassword: .constant(false)
        )
        
        SimpleCleanTextField(
            icon: "person.fill",
            placeholder: "Username",
            text: .constant("")
        )
    }
    .padding()
}
