//
//  SettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section("Account") {
                    NavigationLink(destination: AccountSettingsView()) {
                        Label {
                            Text("Account Settings")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        } icon: {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    NavigationLink(destination: PrivacySettingsView()) {
                        Label {
                            Text("Privacy")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        } icon: {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.green)
                        }
                    }
                    
                    NavigationLink(destination: NotificationSettingsView()) {
                        Label {
                            Text("Notifications")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        } icon: {
                            Image(systemName: "bell.badge")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                
                // Social & Connections Section
                Section {
                    NavigationLink(destination: PeopleDiscoveryView()) {
                        Label {
                            Text("Discover People")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        } icon: {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    NavigationLink(destination: FollowersAnalyticsView()) {
                        Label {
                            Text("Follower Analytics")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("SOCIAL & CONNECTIONS")
                }
                
                // App Section
                Section("App") {
                    NavigationLink(destination: HelpSupportView()) {
                        Label {
                            Text("Help & Support")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        } icon: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.purple)
                        }
                    }
                    
                    NavigationLink(destination: AboutAmenView()) {
                        Label {
                            Text("About AMEN")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.gray)
                        }
                    }
                }
                
                // Developer Tools (Debug only)
                #if DEBUG
                Section("Developer Tools") {
                    NavigationLink {
                        AlgoliaSyncDebugView()
                    } label: {
                        Label {
                            Text("Algolia Sync")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .foregroundStyle(.indigo)
                        }
                    }
                }
                #endif
                
                // Sign Out
                Section {
                    Button(role: .destructive) {
                        signOut()
                    } label: {
                        HStack {
                            Spacer()
                            Label {
                                Text("Sign Out")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                            } icon: {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
    }
    
    private func signOut() {
        authViewModel.signOut()
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationViewModel())
}
