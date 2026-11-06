import SwiftUI

struct WindowSnapPreviewView: View {
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.windowSnapPreview, style: .continuous)
    }

    var body: some View {
        shape
            .fill(Theme.Colors.windowSnapPreviewFill)
            .overlay {
                shape.strokeBorder(
                    Theme.Colors.windowSnapPreviewStroke,
                    lineWidth: Theme.Size.windowSnapPreviewStroke)
            }
            .accessibilityHidden(true)
    }
}
