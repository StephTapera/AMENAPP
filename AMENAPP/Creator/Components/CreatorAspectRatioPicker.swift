import SwiftUI

struct CreatorAspectRatioPicker: View {
    @Binding var selection: CreatorAspectRatio

    var body: some View {
        CreatorSegmentedControl(selection: $selection)
    }
}
