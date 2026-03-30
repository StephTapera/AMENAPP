//
//  FaithTechView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct FaithTechView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: TechCategory = .all
    
    enum TechCategory: String, CaseIterable {
        case all = "All"
        case principles = "Principles"
        case challenges = "Challenges"
        case tools = "Tools"
        case community = "Community"
    }
    
    var filteredArticles: [TechArticle] {
        if selectedCategory == .all {
            return techArticles
        }
        return techArticles.filter { $0.category == selectedCategory.rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TechCategory.allCases, id: \.self) { category in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategory = category
                            }
                        } label: {
                            Text(category.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(selectedCategory == category ? .white : .black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedCategory == category ? Color.black : Color.gray.opacity(0.1))
                                )
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 16)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.orange)
                                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                            
                            Text("Faith & Technology")
                                .font(.custom("OpenSans-Bold", size: 24))
                        }
                        
                        Text("Navigating the digital world with biblical wisdom")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // Featured article
                    FeaturedTechArticle()
                    
                    // Articles
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Latest Articles")
                            .font(.custom("OpenSans-Bold", size: 20))
                            .padding(.horizontal)
                        
                        ForEach(filteredArticles) { article in
                            TechArticleCard(article: article)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Faith & Technology")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeaturedTechArticle: View {
    @State private var shimmerPhase: CGFloat = 0
    @State private var showArticle = false
    
    let featuredArticle = TechArticle(
        title: "Digital Discipleship: Using Technology for God's Glory",
        excerpt: "Explore how we can leverage modern technology while maintaining our faith values and priorities.",
        category: "Principles",
        readTime: "5 min",
        icon: "cpu.fill",
        gradientColors: [.orange, .red]
    )
    
    var body: some View {
        Button {
            showArticle = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Image placeholder
                ZStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 200)
                    
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.3))
                    
                    // Featured badge
                    VStack {
                        HStack {
                            Text("Featured")
                                .font(.custom("OpenSans-Bold", size: 12))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                )
                            
                            Spacer()
                        }
                        .padding()
                        
                        Spacer()
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Digital Discipleship: Using Technology for God's Glory")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    Text("Explore how we can leverage modern technology while maintaining our faith values and priorities.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                    
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                            Text("5 min read")
                                .font(.custom("OpenSans-Regular", size: 12))
                        }
                        .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            showArticle = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Read More")
                                    .font(.custom("OpenSans-Bold", size: 14))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                }
                .padding()
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
            )
            .padding(.horizontal)
        }
        .sheet(isPresented: $showArticle) {
            ArticleDetailView(article: featuredArticle, isBookmarked: .constant(false))
        }
    }
}

struct TechArticleCard: View {
    let article: TechArticle
    @State private var isBookmarked = false
    @State private var showArticle = false
    
    var body: some View {
        Button {
            showArticle = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: article.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: article.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text(article.excerpt)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(article.readTime)
                                .font(.custom("OpenSans-Regular", size: 11))
                        }
                        .foregroundStyle(.secondary)
                        
                        Text(article.category)
                            .font(.custom("OpenSans-SemiBold", size: 10))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.1))
                            )
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isBookmarked.toggle()
                    }
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isBookmarked ? .orange : .secondary)
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
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showArticle) {
            ArticleDetailView(article: article, isBookmarked: $isBookmarked)
        }
    }
}

struct TechArticle: Identifiable {
    let id = UUID()
    let title: String
    let excerpt: String
    let category: String
    let readTime: String
    let icon: String
    let gradientColors: [Color]
    var fullContent: String {
        // Generate full article content based on title
        switch title {
        case "Biblical Wisdom for Social Media":
            return """
            In an age where social media dominates our daily interactions, how can we as Christians navigate these platforms with wisdom and grace?
            
            ## The Challenge
            
            Social media presents unique challenges for believers. The temptation to compare ourselves with others, the echo chambers that reinforce our beliefs without challenge, and the tendency toward shallow interactions can all work against spiritual growth.
            
            ## Biblical Principles
            
            1. **Guard Your Heart** - "Above all else, guard your heart, for everything you do flows from it." (Proverbs 4:23)
            
            2. **Speak Truth in Love** - "Instead, speaking the truth in love, we will grow to become in every respect the mature body of him who is the head, that is, Christ." (Ephesians 4:15)
            
            3. **Build Others Up** - "Do not let any unwholesome talk come out of your mouths, but only what is helpful for building others up according to their needs." (Ephesians 4:29)
            
            ## Practical Steps
            
            - Set time limits on social media usage
            - Follow accounts that encourage spiritual growth
            - Think before you post - will this glorify God?
            - Use platforms to share your faith authentically
            - Take regular social media fasts
            
            ## Conclusion
            
            Social media is a tool, and like any tool, it can be used for good or harm. Let's choose to use it wisely, honoring God in our online presence just as we would in person.
            """
            
        case "Overcoming Digital Addiction":
            return """
            Our phones have become extensions of ourselves. But when do healthy habits cross the line into addiction?
            
            ## Recognizing the Problem
            
            Signs of digital addiction include:
            - Checking your phone first thing in the morning
            - Feeling anxious when away from your device
            - Losing track of time on social media
            - Neglecting relationships for screen time
            
            ## A Biblical Perspective
            
            "Everything is permissible for me—but not everything is beneficial. Everything is permissible for me—but I will not be mastered by anything." (1 Corinthians 6:12)
            
            God calls us to be good stewards of our time and to avoid being enslaved to anything other than Him.
            
            ## Breaking Free
            
            1. **Acknowledge the issue** - Confession is the first step
            2. **Set boundaries** - Use Screen Time features
            3. **Replace the habit** - Fill time with prayer, reading Scripture
            4. **Find accountability** - Share your struggle with trusted friends
            5. **Remember your purpose** - You were made for more than scrolling
            
            ## The Freedom of Sabbath Rest
            
            Consider implementing a "tech Sabbath" - one day per week where you unplug completely and focus on God, family, and rest.
            
            Your phone is a tool to serve you, not the other way around.
            """
            
        case "Christian Apps Worth Using":
            return """
            Technology can be a powerful tool for spiritual growth when used intentionally. Here are some apps that can help strengthen your faith.
            
            ## Bible Study
            
            **YouVersion Bible** - Free, hundreds of translations, reading plans, and community features.
            
            **Blue Letter Bible** - Deep study tools with original language references and commentaries.
            
            **Logos Bible Software** - Professional-grade study tools (premium).
            
            ## Prayer
            
            **Pray.com** - Guided prayers, sleep stories, and worship music.
            
            **Echo Prayer** - Organize prayer lists and journal answered prayers.
            
            **Abide** - Biblical meditation and sleep content.
            
            ## Discipleship
            
            **RightNow Media** - Christian video content for all ages (often free through churches).
            
            **The Bible Project** - Animated biblical storytelling and resources.
            
            **She Reads Truth / He Reads Truth** - Beautiful devotionals and reading plans.
            
            ## Community
            
            **Glorify** - Worship music and guided prayers.
            
            **Church Center** - Connect with your local church.
            
            ## Making It Work
            
            Remember: Apps are tools, not replacements for in-person community, Scripture reading, or prayer. Use them to supplement, not substitute, your spiritual practices.
            """
            
        case "Building Online Faith Communities":
            return """
            The digital age has opened new possibilities for Christian fellowship. Here's how to create meaningful online spaces for faith.
            
            ## Why Online Communities Matter
            
            - Reach people who can't attend in person
            - Connect believers across geographical boundaries
            - Provide support 24/7
            - Create spaces for vulnerable conversations
            
            ## Best Practices
            
            ### 1. Set Clear Values
            Define what your community stands for. Create guidelines that reflect biblical values while fostering grace and authenticity.
            
            ### 2. Moderate Wisely
            "Whoever guards his mouth preserves his life; he who opens wide his lips comes to ruin." (Proverbs 13:3)
            
            Have clear moderation policies and enforce them consistently with love.
            
            ### 3. Foster Real Relationships
            Online community should lead to real connection. Encourage:
            - Video calls
            - In-person meetups when possible
            - Prayer partnerships
            - Mentorship relationships
            
            ### 4. Provide Value
            Share content that edifies:
            - Daily devotionals
            - Prayer requests and celebrations
            - Biblical teaching
            - Encouraging testimonies
            
            ### 5. Bridge Online and Offline
            The goal of online community isn't to replace in-person fellowship but to enhance it. Use digital tools to strengthen local connections.
            
            ## Tools for Building Community
            
            - Discord servers for real-time chat
            - Facebook Groups for broader discussions
            - Zoom for Bible studies
            - GroupMe for prayer chains
            
            Remember: Technology enables connection, but the Holy Spirit creates community.
            """
            
        case "Tech Sabbath: Rest in a Digital Age":
            return """
            God commanded rest for a reason. In our always-on digital world, how can we practice biblical Sabbath?
            
            ## The Biblical Foundation
            
            "Remember the Sabbath day by keeping it holy. Six days you shall labor and do all your work, but the seventh day is a sabbath to the Lord your God." (Exodus 20:8-10)
            
            The principle of Sabbath isn't about legalism—it's about trust, rest, and relationship with God.
            
            ## Why We Need Digital Sabbath
            
            Constant connectivity leads to:
            - Mental exhaustion
            - Spiritual dryness
            - Relational distance
            - Anxiety and FOMO
            - Loss of wonder and presence
            
            ## How to Practice Tech Sabbath
            
            ### Choose Your Day
            Pick one day per week (doesn't have to be Sunday) to unplug.
            
            ### Prepare in Advance
            - Notify important contacts
            - Download any needed content offline
            - Finish urgent tasks beforehand
            - Plan enriching activities
            
            ### What to Do Instead
            
            - Extended prayer and Bible reading
            - Quality time with family
            - Nature walks
            - Creative hobbies
            - Face-to-face conversations
            - Physical rest
            
            ### Start Small
            
            If a full day feels overwhelming:
            1. Start with a few hours
            2. Try tech-free mornings
            3. No screens after dinner
            4. Build up to a full day
            
            ## The Fruit of Rest
            
            "Come to me, all you who are weary and burdened, and I will give you rest." (Matthew 11:28)
            
            Sabbath rest reconnects us with God's rhythm and reminds us that the world doesn't depend on our constant availability.
            
            Your worth isn't in your productivity or responsiveness—it's in being God's beloved child.
            """
            
        case "Guarding Your Heart Online":
            return """
            The internet is a minefield of content that can corrupt our minds and hearts. How do we navigate it with purity?
            
            ## The Battle for Your Mind
            
            "Finally, brothers and sisters, whatever is true, whatever is noble, whatever is right, whatever is pure, whatever is lovely, whatever is admirable—if anything is excellent or praiseworthy—think about such things." (Philippians 4:8)
            
            What we consume shapes who we become. Digital content is no exception.
            
            ## Common Dangers
            
            - Pornography and sexual content
            - Violent or disturbing media
            - Toxic comparison and envy
            - Divisive and hateful rhetoric
            - Conspiracy theories and false teaching
            
            ## Practical Protection
            
            ### 1. Install Filters
            Use tools like:
            - Covenant Eyes
            - Bark
            - Circle
            - Screen Time (iOS)
            - Digital Wellbeing (Android)
            
            ### 2. Create Accountability
            Share your struggle with a trusted friend. Give them access to your internet history if needed.
            
            ### 3. Guard Your Gates
            
            "I will refuse to look at anything vile and vulgar." (Psalm 101:3 NLT)
            
            - Unfollow accounts that tempt you
            - Use Incognito/Private browsing accountability
            - Keep devices out of bedroom
            - Use public spaces for internet use
            
            ### 4. Fill Your Mind with Truth
            
            Nature abhors a vacuum. Replace harmful content with:
            - Scripture memorization
            - Worship music
            - Christian podcasts
            - Edifying books
            
            ### 5. When You Fall
            
            "If we confess our sins, he is faithful and just and will forgive us our sins and purify us from all unrighteousness." (1 John 1:9)
            
            Don't let shame keep you from repentance. God's grace is greater than your sin.
            
            ## The Goal
            
            Not just avoiding evil, but pursuing holiness. Let your online life glorify God.
            """
            
        case "Bible Study Apps Comparison":
            return """
            With so many Bible apps available, which one is right for you? Here's a comprehensive comparison.
            
            ## YouVersion Bible
            
            **Price:** Free
            **Best For:** General reading and devotionals
            
            ✅ Pros:
            - 2,000+ Bible versions
            - Reading plans for all levels
            - Social features
            - Beautiful design
            - Audio Bibles
            
            ❌ Cons:
            - Limited study tools
            - Ads in free version
            - No offline commentaries
            
            ## Blue Letter Bible
            
            **Price:** Free
            **Best For:** In-depth study
            
            ✅ Pros:
            - Interlinear Hebrew/Greek
            - Multiple commentaries
            - Cross-references
            - Word studies
            - Completely free
            
            ❌ Cons:
            - Less modern interface
            - Fewer reading plans
            - Steep learning curve
            
            ## Logos Bible Software
            
            **Price:** $0-$1,500+
            **Best For:** Seminary students, pastors, serious students
            
            ✅ Pros:
            - Most comprehensive library
            - Professional research tools
            - Advanced word studies
            - Sermon prep features
            
            ❌ Cons:
            - Expensive
            - Overwhelming for beginners
            - Requires significant storage
            
            ## ESV Bible App
            
            **Price:** Free (ESV), $14.99+ for other translations
            **Best For:** ESV readers who want quality study tools
            
            ✅ Pros:
            - Excellent ESV experience
            - Quality study notes
            - Reading plans
            - Clean interface
            
            ❌ Cons:
            - Limited translations
            - Pay for premium features
            
            ## Olive Tree Bible Software
            
            **Price:** Free + paid resources
            **Best For:** Balance of features and cost
            
            ✅ Pros:
            - Good balance of depth and usability
            - Fair pricing model
            - Cross-platform sync
            - Quality commentaries
            
            ❌ Cons:
            - Dated interface
            - Fragmented purchases
            
            ## Recommendation
            
            **Beginners:** Start with YouVersion
            **Intermediate:** Blue Letter Bible or ESV App
            **Advanced:** Logos or Olive Tree
            
            **Best Combo:** YouVersion for reading plans + Blue Letter Bible for study
            
            Remember: The best Bible app is the one you'll actually use. Start simple and grow from there.
            """
            
        case "Online Ministry Best Practices":
            return """
            Digital ministry is no longer optional—it's essential. Here's how to do it well.
            
            ## The Digital Mission Field
            
            "Go into all the world and preach the gospel to all creation." (Mark 16:15)
            
            Today, "all the world" includes the digital world. Billions of people spend hours online daily—that's our mission field.
            
            ## Core Principles
            
            ### 1. Authenticity Over Production Value
            
            People crave genuine connection, not polished perfection. A heartfelt phone video often connects better than professional production.
            
            ### 2. Consistency Matters
            
            "Let us not become weary in doing good, for at the proper time we will reap a harvest if we do not give up." (Galatians 6:9)
            
            Regular content builds trust and community.
            
            ### 3. Meet People Where They Are
            
            Different platforms reach different audiences:
            - **Instagram/TikTok:** Younger generations
            - **Facebook:** Older demographics
            - **YouTube:** Long-form content
            - **Podcast:** Commuters and busy people
            
            ### 4. Serve, Don't Sell
            
            Focus on giving value, not promoting yourself or your church.
            
            ## Content Ideas
            
            - 60-second Scripture reflections
            - Answering tough questions
            - Behind-the-scenes of ministry
            - Testimony stories
            - Practical Christian living tips
            - Prayer live streams
            - Bible study series
            
            ## Engagement Strategies
            
            ### Respond to Comments
            Every comment is a person seeking connection. Reply thoughtfully.
            
            ### Ask Questions
            Prompt discussion with engaging questions.
            
            ### Go Live
            Live video creates urgency and real-time connection.
            
            ### Use Stories
            Instagram/Facebook stories are perfect for daily devotionals.
            
            ## Common Mistakes to Avoid
            
            ❌ Only posting when convenient
            ❌ Ignoring negative comments
            ❌ Using too much Christian jargon
            ❌ Making everything about your church
            ❌ Not measuring what works
            
            ## Measuring Success
            
            Look beyond vanity metrics:
            - Are people engaging meaningfully?
            - Are lives being changed?
            - Are disciples being made?
            - Is the gospel being shared?
            
            ## Remember
            
            "I planted the seed, Apollos watered it, but God has been making it grow." (1 Corinthians 3:6)
            
            Your job is faithfulness, not results. God grows His kingdom.
            """
            
        default:
            return """
            \(title)
            
            \(excerpt)
            
            This article explores important aspects of navigating technology as a Christian in today's digital world.
            
            ## Key Principles
            
            - Honor God in all things
            - Use technology as a tool, not a master
            - Build authentic relationships
            - Guard your heart and mind
            - Serve others through digital platforms
            
            ## Practical Application
            
            Consider how you can apply these principles in your daily digital life. Remember, technology is neutral—it's how we use it that matters.
            
            ## Reflection Questions
            
            1. How is God calling you to use technology?
            2. What boundaries do you need to set?
            3. How can you use digital tools to serve others?
            
            May God guide you as you navigate the digital world with wisdom and grace.
            """
        }
    }
}

// MARK: - Article Detail View

struct ArticleDetailView: View {
    @Environment(\.dismiss) var dismiss
    let article: TechArticle
    @Binding var isBookmarked: Bool
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero section
                    ZStack(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: article.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 250)
                        
                        Image(systemName: article.icon)
                            .font(.system(size: 100))
                            .foregroundStyle(.white.opacity(0.2))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 40)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(article.category)
                                .font(.custom("OpenSans-Bold", size: 12))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.3))
                                )
                            
                            Text(article.title)
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                    }
                    
                    // Article metadata
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 14))
                            Text(article.readTime)
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                        .foregroundStyle(.secondary)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                            Text("Today")
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                        .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    
                    // Article content
                    Text(article.fullContent)
                        .font(.custom("OpenSans-Regular", size: 17))
                        .foregroundStyle(.primary)
                        .lineSpacing(8)
                        .padding(.horizontal, 24)
                    
                    Divider()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    
                    // Related articles
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Related Articles")
                            .font(.custom("OpenSans-Bold", size: 20))
                            .padding(.horizontal, 24)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(techArticles.filter { $0.id != article.id }.prefix(3)) { relatedArticle in
                                    RelatedArticleCard(article: relatedArticle)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isBookmarked.toggle()
                                let haptic = UIImpactFeedbackGenerator(style: .medium)
                                haptic.impactOccurred()
                            }
                        } label: {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 20))
                                .foregroundStyle(isBookmarked ? .orange : .secondary)
                        }
                        
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [article.title])
            }
        }
    }
}

// MARK: - Related Article Card

struct RelatedArticleCard: View {
    let article: TechArticle
    @State private var showArticle = false
    
    var body: some View {
        Button {
            showArticle = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: article.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 200, height: 120)
                    
                    Image(systemName: article.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Text(article.title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(width: 200, alignment: .leading)
                
                Text(article.readTime)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showArticle) {
            ArticleDetailView(article: article, isBookmarked: .constant(false))
        }
    }
}

// MARK: - Sample Data

let techArticles = [
    TechArticle(
        title: "Biblical Wisdom for Social Media",
        excerpt: "How to use social platforms while honoring God and building authentic relationships",
        category: "Principles",
        readTime: "4 min",
        icon: "person.2.fill",
        gradientColors: [.blue, .cyan]
    ),
    TechArticle(
        title: "Overcoming Digital Addiction",
        excerpt: "Finding freedom from smartphone dependency through faith and practical strategies",
        category: "Challenges",
        readTime: "6 min",
        icon: "iphone",
        gradientColors: [.red, .orange]
    ),
    TechArticle(
        title: "Christian Apps Worth Using",
        excerpt: "Discover apps that help you grow spiritually and stay connected with your faith",
        category: "Tools",
        readTime: "5 min",
        icon: "square.grid.2x2.fill",
        gradientColors: [.green, .teal]
    ),
    TechArticle(
        title: "Building Online Faith Communities",
        excerpt: "Creating meaningful digital spaces for fellowship, prayer, and spiritual growth",
        category: "Community",
        readTime: "7 min",
        icon: "network",
        gradientColors: [.purple, .pink]
    ),
    TechArticle(
        title: "Tech Sabbath: Rest in a Digital Age",
        excerpt: "The importance of unplugging and spending intentional time with God",
        category: "Principles",
        readTime: "5 min",
        icon: "moon.stars.fill",
        gradientColors: [.indigo, .blue]
    ),
    TechArticle(
        title: "Guarding Your Heart Online",
        excerpt: "Protecting your mind and spirit from harmful digital content",
        category: "Challenges",
        readTime: "6 min",
        icon: "shield.fill",
        gradientColors: [.orange, .yellow]
    ),
    TechArticle(
        title: "Bible Study Apps Comparison",
        excerpt: "A comprehensive look at the best digital tools for Scripture study",
        category: "Tools",
        readTime: "8 min",
        icon: "book.fill",
        gradientColors: [.cyan, .blue]
    ),
    TechArticle(
        title: "Online Ministry Best Practices",
        excerpt: "Effective strategies for reaching people with the Gospel digitally",
        category: "Community",
        readTime: "7 min",
        icon: "megaphone.fill",
        gradientColors: [.pink, .red]
    )
]

#Preview {
    FaithTechView()
}
