import SwiftUI

/// 通用海报卡片（推荐页用）
struct PosterCard: View {
    let name: String
    let image: String?
    var onTap: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: KZ.imgRadius).fill(KZ.card)
                    if let s = image, let u = URL(string: s) {
                        AsyncImage(url: u) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Text(name.prefix(1))
                                    .font(.system(size: 52, weight: .thin))
                                    .foregroundStyle(KZ.dim)
                            }
                        }
                    } else {
                        Text(name.prefix(1))
                            .font(.system(size: 52, weight: .thin))
                            .foregroundStyle(KZ.dim)
                    }
                }
                .aspectRatio(1/KZ.posterRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: KZ.imgRadius))
                .focusCard(focused)

                Text(name)
                    .font(.system(size: 16))
                    .lineLimit(2)
                    .foregroundStyle(KZ.label)
            }
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
