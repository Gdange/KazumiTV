import SwiftUI

/// 详情页的五个 Tab（对齐官方 info_page.dart：概览/吐槽/角色/关联/制作人员）
enum InfoTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case comments = "吐槽"
    case characters = "角色"
    case relations = "关联"
    case staff = "制作人员"
    var id: String { rawValue }
}

struct CommentList: View {
    let comments: [BgmComment]

    var body: some View {
        if comments.isEmpty {
            placeholder("还没有吐槽")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(comments) { c in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text(c.user).font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(KZ.accent)
                                if c.rate > 0 {
                                    HStack(spacing: 2) {
                                        ForEach(0..<5, id: \.self) { i in
                                            Image(systemName: i < c.rate / 2 ? "star.fill" : "star")
                                                .font(.system(size: 9))
                                        }
                                    }.foregroundStyle(KZ.dim)
                                }
                                Spacer()
                            }
                            Text(c.text)
                                .font(.system(size: 14))
                                .foregroundStyle(KZ.label)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card))
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct CharacterGrid: View {
    let characters: [BgmCharacter]

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        if characters.isEmpty {
            placeholder("没有角色资料")
        } else {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(characters) { c in
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(KZ.card)
                                if let s = c.image, let u = URL(string: s) {
                                    AsyncImage(url: u) { p in
                                        if case .success(let img) = p { img.resizable().scaledToFill() }
                                        else { Text(c.name.prefix(1)).foregroundStyle(KZ.dim) }
                                    }
                                } else {
                                    Text(c.name.prefix(1)).foregroundStyle(KZ.dim)
                                }
                            }
                            .frame(height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Text(c.name).font(.system(size: 13)).lineLimit(1)
                            Text(c.relation).font(.system(size: 11)).foregroundStyle(KZ.dim).lineLimit(1)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct RelationList: View {
    let relations: [BgmRelation]

    var body: some View {
        if relations.isEmpty {
            placeholder("没有关联条目")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(relations) { r in
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(KZ.card)
                                if let s = r.image, let u = URL(string: s) {
                                    AsyncImage(url: u) { p in
                                        if case .success(let img) = p { img.resizable().scaledToFill() }
                                        else { EmptyView() }
                                    }
                                }
                            }
                            .frame(width: 44, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.system(size: 15))
                                Text(r.relation).font(.system(size: 12)).foregroundStyle(KZ.dim)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card))
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct StaffList: View {
    let staff: [BgmStaff]

    var body: some View {
        if staff.isEmpty {
            placeholder("没有制作人员资料")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(staff) { p in
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(KZ.card)
                                if let s = p.image, let u = URL(string: s) {
                                    AsyncImage(url: u) { ph in
                                        if case .success(let img) = ph {
                                            img.resizable().scaledToFill()
                                        } else { Text(p.name.prefix(1)).foregroundStyle(KZ.dim) }
                                    }
                                } else {
                                    Text(p.name.prefix(1)).font(.system(size: 14)).foregroundStyle(KZ.dim)
                                }
                            }
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())

                            Text(p.name).font(.system(size: 15))
                            Spacer()
                            Text(p.relation).font(.system(size: 13)).foregroundStyle(KZ.dim)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(KZ.card))
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

private func placeholder(_ text: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: "tray").font(.system(size: 40, weight: .thin)).foregroundStyle(KZ.dim)
        Text(text).font(.system(size: 15)).foregroundStyle(KZ.dim)
    }
    .frame(maxWidth: .infinity, minHeight: 200)
}
