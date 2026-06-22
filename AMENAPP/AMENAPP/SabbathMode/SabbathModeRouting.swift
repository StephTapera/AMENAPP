// SabbathModeRouting.swift
// AMENAPP — SabbathMode
//
// Navigation router for SabbathWindowView.onSurfaceSelect.
// Maps each SabbathSurface to the correct existing view.
// Wired into ContentView additively (see ContentView.swift SabbathMode section).
//
// Surface → destination:
//   scripture        → SelahScriptureReaderView (KJV, Psalm 1)
//   prayer           → PrayerRoomView
//   bereanGuide      → SabbathBereanGuideView(task: .sabbathGuide)
//   churchNotes      → ChurchNotesView
//   findChurch       → FindChurchView
//   spaces           → AmenConnectSpacesHubView
//   familyQuestions  → SabbathBereanGuideView(task: .familyQuestions)
//   reflection       → SabbathBereanGuideView(task: .reflectionPrompt)

import SwiftUI

// MARK: - Destination enum

/// Destination enum for Sabbath surface navigation.
enum SabbathNavDestination: Identifiable {
    case scripture
    case prayer
    case bereanGuide(SabbathAITask)
    case churchNotes
    case findChurch
    case spaces

    var id: String {
        switch self {
        case .scripture:            return "scripture"
        case .prayer:               return "prayer"
        case .bereanGuide(let t):   return "bereanGuide_\(t.rawValue)"
        case .churchNotes:          return "churchNotes"
        case .findChurch:           return "findChurch"
        case .spaces:               return "spaces"
        }
    }
}

// MARK: - Surface → destination mapping

/// Maps a SabbathSurface to its navigation destination.
func sabbathNavDestination(for surface: SabbathSurface) -> SabbathNavDestination {
    switch surface {
    case .scripture:        return .scripture
    case .prayer:           return .prayer
    case .bereanGuide:      return .bereanGuide(.sabbathGuide)
    case .churchNotes:      return .churchNotes
    case .findChurch:       return .findChurch
    case .spaces:           return .spaces
    case .familyQuestions:  return .bereanGuide(.familyQuestions)
    case .reflection:       return .bereanGuide(.reflectionPrompt)
    }
}

// MARK: - Destination view builder

/// SwiftUI destination view builder for Sabbath surface navigation.
/// Used inside .fullScreenCover on the SabbathWindowView host.
@MainActor
@ViewBuilder
func sabbathDestinationView(
    for destination: SabbathNavDestination,
    selectedTab: Binding<Int>,
    dismiss: @escaping () -> Void
) -> some View {
    switch destination {

    case .scripture:
        // Scripture → Selah Scripture Reader (KJV, Psalm 1 as entry point)
        NavigationStack {
            SelahScriptureReaderView(
                initialReference: SelahScriptureReference(
                    bookId: "psalms",
                    chapter: 1,
                    startVerse: nil,
                    endVerse: nil
                ),
                provider: SelahLocalPublicDomainBibleProvider(),
                preferencesStore: SelahScriptureReaderPreferencesStore(
                    defaults: UserDefaults(suiteName: "sabbath.scripture") ?? .standard
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }

    case .prayer:
        // Prayer → PrayerView (the full prayer wall / request flow, no required params)
        NavigationStack {
            PrayerView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }

    case .bereanGuide(let task):
        // Berean guide tasks → SabbathBereanGuideView
        NavigationStack {
            SabbathBereanGuideView(task: task, onClose: dismiss)
                .navigationBarHidden(true)
        }

    case .churchNotes:
        // Church Notes → ChurchNotesView
        NavigationStack {
            ChurchNotesView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }

    case .findChurch:
        // Find a Church → FindChurchView
        NavigationStack {
            FindChurchView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }

    case .spaces:
        // Spaces → AmenConnectSpacesHubView
        NavigationStack {
            AmenConnectSpacesHubView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
