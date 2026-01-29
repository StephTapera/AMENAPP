//
//  ResourceDetailViews.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI


// MARK: - Sermon Summarizer View

struct SermonSummarizerView: View {
    @State private var sermonText = ""
    @State private var summary = ""
    @State private var keyPoints: [String] = []
    @State private var isAnalyzing = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Paste your sermon notes or transcript below, and AI will generate a summary with key takeaways.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sermon Content")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .padding(.horizontal)
                    
                    TextEditor(text: $sermonText)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .frame(minHeight: 200)
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                
                Button {
                    analyzeSermon()
                } label: {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isAnalyzing ? "Analyzing..." : "Generate Summary")
                            .font(.custom("OpenSans-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(colors: [.teal, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(14)
                }
                .disabled(sermonText.isEmpty || isAnalyzing)
                .padding(.horizontal)
                
                if !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Summary")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .padding(.horizontal)
                        
                        Text(summary)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .padding()
                            .background(Color.teal.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        
                        if !keyPoints.isEmpty {
                            Text("Key Takeaways")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                ForEach(keyPoints, id: \.self) { point in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.teal)
                                        Text(point)
                                            .font(.custom("OpenSans-Regular", size: 14))
                                        Spacer()
                                    }
                                }
                            }
                            .padding()
                            .background(Color.teal.opacity(0.05))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
    
    private func analyzeSermon() {
        isAnalyzing = true
        
        // Simulate AI processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            summary = "This sermon focused on the transformative power of God's grace in our daily lives. The speaker emphasized that true faith isn't just about belief, but about allowing God's love to shape our actions and relationships with others."
            
            keyPoints = [
                "Grace is not earned - it's freely given by God",
                "Faith should transform how we treat others",
                "Daily prayer deepens our relationship with God",
                "Living out faith requires both belief and action"
            ]
            
            isAnalyzing = false
        }
    }
}

// MARK: - Faith in Business View

struct FaithInBusinessView: View {
    let principles = [
        BusinessPrinciple(
            icon: "heart.fill",
            iconColor: .red,
            title: "Lead with Integrity",
            description: "Be honest in all your business dealings",
            scripture: "The integrity of the upright guides them.",
            reference: "Proverbs 11:3"
        ),
        BusinessPrinciple(
            icon: "hand.raised.fill",
            iconColor: .blue,
            title: "Serve Others",
            description: "Put service above self-interest",
            scripture: "Serve wholeheartedly, as if you were serving the Lord.",
            reference: "Ephesians 6:7"
        ),
        BusinessPrinciple(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: .green,
            title: "Steward Resources",
            description: "Manage finances and resources wisely",
            scripture: "Moreover, it is required of stewards that they be found faithful.",
            reference: "1 Corinthians 4:2"
        ),
        BusinessPrinciple(
            icon: "person.3.fill",
            iconColor: .purple,
            title: "Value People",
            description: "Treat employees and customers with respect",
            scripture: "Do nothing from selfish ambition or conceit, but in humility count others more significant.",
            reference: "Philippians 2:3"
        ),
        BusinessPrinciple(
            icon: "cross.fill",
            iconColor: .orange,
            title: "Honor God",
            description: "Make decisions that glorify God",
            scripture: "Whatever you do, do all to the glory of God.",
            reference: "1 Corinthians 10:31"
        ),
        BusinessPrinciple(
            icon: "gift.fill",
            iconColor: .pink,
            title: "Practice Generosity",
            description: "Give back to your community and those in need",
            scripture: "In all things I have shown you that by working hard in this way we must help the weak.",
            reference: "Acts 20:35"
        )
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Faith in Business")
                        .font(.custom("OpenSans-Bold", size: 32))
                        .padding(.horizontal)
                    
                    Text("Biblical principles for marketplace leaders. Honor God in your business by leading with integrity, serving others, and stewarding resources wisely.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                // Featured Quote
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 20))
                            .foregroundStyle(.brown.opacity(0.6))
                        
                        Text("Work as unto the Lord")
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.primary)
                    }
                    
                    Text("\"Whatever you do, work heartily, as for the Lord and not for men, knowing that from the Lord you will receive the inheritance as your reward. You are serving the Lord Christ.\"")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineSpacing(4)
                    
                    Text("Colossians 3:23-24")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.brown)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.brown.opacity(0.1), Color.orange.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                )
                .padding(.horizontal)
                
                // Principles Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Biblical Business Principles")
                        .font(.custom("OpenSans-Bold", size: 22))
                        .padding(.horizontal)
                    
                    ForEach(principles) { principle in
                        BusinessPrincipleCard(principle: principle)
                    }
                }
                
                // Action Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Take Action")
                        .font(.custom("OpenSans-Bold", size: 22))
                        .padding(.horizontal)
                    
                    ActionCard(
                        icon: "list.bullet.clipboard",
                        iconColor: .blue,
                        title: "Weekly Reflection",
                        description: "Set aside time each week to reflect on how you're applying these principles in your business."
                    )
                    
                    ActionCard(
                        icon: "person.2.fill",
                        iconColor: .green,
                        title: "Find Accountability",
                        description: "Join or form a group of Christian business leaders for mutual support and accountability."
                    )
                    
                    ActionCard(
                        icon: "book.fill",
                        iconColor: .purple,
                        title: "Continue Learning",
                        description: "Study the lives of biblical entrepreneurs like Joseph, Lydia, and Aquila & Priscilla."
                    )
                }
            }
            .padding(.vertical)
        }
    }
}
struct BusinessPrinciple: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let scripture: String
    let reference: String
}

struct BusinessPrincipleCard: View {
    let principle: BusinessPrinciple
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(principle.iconColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: principle.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(principle.iconColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(principle.title)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.primary)
                        
                        Text(principle.description)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(principle.scripture)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)
                            .italic()
                            .lineSpacing(4)
                        
                        Text(principle.reference)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(principle.iconColor)
                    }
                    .padding(.top, 4)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

struct ActionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
        .padding(.horizontal)
    }
}
