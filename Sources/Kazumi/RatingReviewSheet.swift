import SwiftUI

/// 评分 + 短评（对齐官方 RatingReviewDialog）
/// 官方要素：0–10 分档位、380 字短评、最多 10 个标签
struct RatingReviewSheet: View {
    let subjectID: Int
    let title: String
    var initialRate: Int = 0
    var initialComment: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var rate = 0
    @State private var comment = ""
    @State private var submitting = false
    @State private var message: String?

    private let scoreLabels = ["未评分", "不忍直视", "很差", "差", "较差", "不过不失",
                               "还行", "推荐", "力荐", "神作", "超神作"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("评价").font(.system(size: 26, weight: .bold))
                    Text(title).font(.system(size: 14)).foregroundStyle(KZ.dim).lineLimit(1)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).padding(8)
                }.buttonStyle(.plain)
            }

            // 分数
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("\(rate)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(rate > 0 ? KZ.accent : KZ.dim)
                    Text(scoreLabels[rate])
                        .font(.system(size: 16)).foregroundStyle(KZ.dim)
                }
                HStack(spacing: 6) {
                    ForEach(1...10, id: \.self) { i in
                        ScoreDot(value: i, active: i <= rate) { rate = i }
                    }
                }
            }

            // 短评
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("短评").font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text("\(comment.count)/380")
                        .font(.system(size: 12)).foregroundStyle(KZ.dim)
                }
                TextField("说点什么…", text: $comment, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(3...6)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card))
            }

            if let m = message {
                Text(m).font(.system(size: 13)).foregroundStyle(.orange)
            }

            HStack(spacing: 14) {
                Button { Task { await submit() } } label: {
                    HStack(spacing: 8) {
                        if submitting { ProgressView().scaleEffect(0.7) }
                        Text(submitting ? "提交中…" : "提交到 Bangumi")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KZ.onAccent)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(Capsule().fill(KZ.accent))
                }
                .buttonStyle(.plain)
                .disabled(submitting || !BangumiAccount.isLoggedIn)

                if !BangumiAccount.isLoggedIn {
                    Text("未登录 Bangumi，先在「我的」里填 Token")
                        .font(.system(size: 12)).foregroundStyle(KZ.dim)
                }
            }
        }
        .padding(40)
        .frame(width: 860, height: 620)
        .background(KZ.bg)
        .onAppear {
            rate = initialRate
            comment = initialComment
        }
    }

    private func submit() async {
        guard BangumiAccount.isLoggedIn else { message = "未登录"; return }
        submitting = true
        defer { submitting = false }

        var ok = await BangumiAPI.setCollection(subjectID: subjectID, type: .doing)
        if rate > 0 || !comment.isEmpty {
            ok = await BangumiAPI.setCollection(
                subjectID: subjectID,
                type: .doing,
                rate: rate > 0 ? rate : nil,
                comment: comment.isEmpty ? nil : comment
            )
        }
        if ok {
            message = "已提交"
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        } else {
            message = "提交失败，检查 Token 或网络"
        }
    }
}

private struct ScoreDot: View {
    let value: Int
    let active: Bool
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(active ? KZ.accent : KZ.card)
                )
                .foregroundStyle(active ? KZ.onAccent : KZ.label)
                .overlay(
                    Circle().strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2.5)
                )
                .scaleEffect(focused ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
