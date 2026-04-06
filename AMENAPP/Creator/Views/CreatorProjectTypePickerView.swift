import SwiftUI

struct CreatorProjectTypePickerView: View {
    @Binding var selection: CreatorProjectType

    var body: some View {
        CreatorSegmentedControl(selection: $selection)
    }
}
