import SwiftUI

struct ChapterButton: View {
    let chapter: Chapter
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(chapter.name)
                .font(.system(size: 15))
                .lineLimit(1)
                .foregroundStyle(focused ? KZ.onAccent : KZ.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(focused ? KZ.accent : KZ.card)
                )
                .scaleEffect(focused ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.14), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
