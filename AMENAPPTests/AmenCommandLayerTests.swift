import Testing
@testable import AMENAPP

@Suite("Amen command layer")
struct AmenCommandLayerTests {
    @Test func homeCatalogIncludesRequiredCommandActions() {
        let actionIDs = Set(AmenCommandLayerCatalog.actions(for: .home).map(\.id))
        let required: Set<AmenCommandLayerActionID> = [
            .askBerean,
            .prayerRequest,
            .testimony,
            .churchNote,
            .reflection,
            .createImage,
            .deepStudy,
            .webSearch,
            .addFiles,
            .aiMeetingNotes,
            .startSpace,
            .rsvpEvent,
            .camera,
            .photos,
            .openCommandPalette
        ]

        #expect(required.isSubset(of: actionIDs))
    }

    @Test func unavailableHomeActionsHaveUserVisibleReasons() {
        let unavailable = AmenCommandLayerCatalog.actions(for: .home).filter { !$0.isAvailable }

        #expect(!unavailable.isEmpty)
        #expect(unavailable.allSatisfy { action in
            guard let reason = action.unavailableReason else { return false }
            return !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }

    @MainActor
    @Test func homeAttachmentActionsDeclarePermissionsAndPickerRoutes() {
        let routes: [(AmenCommandLayerActionID, AmenCommandLayerPermissionType, BereanAttachmentPickerMode)] = [
            (.addFiles, .files, .file),
            (.photos, .photos, .photo),
            (.camera, .camera, .camera)
        ]

        for route in routes {
            #expect(route.0.commandLayerPermissionType == route.1)
            #expect(route.0.homeAttachmentPickerMode == route.2)
        }
    }

    @Test func surfacesHaveNonEmptyPlaceholdersAndNavigationChips() {
        for surface in AmenCommandLayerSurface.allCases {
            #expect(!surface.placeholder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!surface.navigationChips.isEmpty)
            #expect(surface.navigationChips.allSatisfy { chip in
                !chip.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !chip.systemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        }
    }

    @Test func everyCatalogActionHasDisplayMetadata() {
        for surface in AmenCommandLayerSurface.allCases {
            for action in AmenCommandLayerCatalog.actions(for: surface) {
                #expect(!action.id.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!action.id.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!action.id.systemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
