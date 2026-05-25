//
//  ProjectIconPickerView.swift
//  DevCal
//
//  Lets the user pick a project icon by either uploading a photo or choosing
//  a Phosphor fill glyph from a curated library. Selections are mutually
//  exclusive — picking an upload clears the Phosphor name and vice versa.
//  When both are nil, the project falls back to its `kind.defaultPhName`.
//

import SwiftUI
import PhotosUI
import PhosphorSymbols

/// Renders the right icon for a Project given its three possible sources:
/// uploaded image → user-picked Phosphor fill → kind default.
struct ProjectIconView: View {
    let imageData: Data?
    let phName: String?
    let kindFallback: ProjectKind
    var size: CGFloat = 24
    /// Stored hex (nil → Theme.brand). Only applies to glyph rendering;
    /// uploaded images keep their authored colors.
    var colorHex: String? = nil

    var body: some View {
        if let data = imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            // Glyph variant: tinted icon centered in a same-size rounded
            // square painted at 10% of the icon color — mirrors the iOS
            // app-icon vocabulary and matches the uploaded-image footprint.
            let color = Theme.iconColor(colorHex)
            Image(ph: phName ?? kindFallback.defaultPhName, weight: .fill)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.6, height: size * 0.6)
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(color.opacity(0.1))
                }
        }
    }
}

struct ProjectIconPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var iconImageData: Data?
    @Binding var iconPhName: String?
    @Binding var iconColorHex: String?
    let kindFallback: ProjectKind

    @State private var photoItem: PhotosPickerItem?

    private static let phosphorOptions: [String] = [
        // Devices / apps
        "device-mobile", "device-tablet", "monitor", "laptop", "devices", "watch",
        // Web / network
        "globe", "browser", "browsers", "cloud", "network", "planet",
        // Game
        "game-controller", "joystick", "dice-six", "sword", "trophy", "target",
        // Plugin / extension / tools
        "puzzle-piece", "plug", "plugs-connected", "wrench", "gear", "magic-wand",
        // Dev
        "terminal-window", "code", "code-block", "brackets-curly", "git-branch",
        // Template / design
        "squares-four", "layout", "frame-corners", "palette", "paint-brush", "shapes",
        // Assets / media
        "image-square", "image", "file-image", "music-notes", "video-camera", "microphone",
        // Course / education
        "graduation-cap", "book", "books", "chalkboard-teacher", "presentation", "certificate", "student",
        // Branding / energy
        "rocket", "lightning", "lightbulb", "sparkle", "star", "heart", "fire", "flag",
        // Productivity
        "calendar", "clock", "timer", "list-checks", "kanban", "notebook", "pencil",
        // AI
        "robot", "brain",
        // Commerce
        "currency-dollar", "coin", "wallet", "piggy-bank", "chart-line-up", "package", "shopping-bag"
    ]

    private let columns = [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    previewHeader
                    uploadRow
                    IconColorPaletteView(selection: $iconColorHex)
                    sectionHeader("圖示庫")
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Self.phosphorOptions, id: \.self) { name in
                            symbolTile(name)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
            .background(Theme.appBackground)
            .navigationTitle("選擇圖示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .cancelActionStyle()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .confirmActionStyle()
                }
            }
            .onChange(of: photoItem) { _, newItem in
                Task { await loadPhoto(newItem) }
            }
        }
    }

    // MARK: - Sections

    private var previewHeader: some View {
        HStack(spacing: 16) {
            self.previewBox

            VStack(alignment: .leading, spacing: 4) {
                Text(currentSourceLabel)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(Theme.primaryText)
                if iconImageData != nil || iconPhName != nil {
                    Button {
                        withAnimation { resetToDefault() }
                    } label: {
                        Text("回復預設")
                            .appFont(.footnote)
                            .foregroundStyle(Theme.primaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var previewBox: some View {
        ProjectIconView(
            imageData: iconImageData,
            phName: iconPhName,
            kindFallback: kindFallback,
            size: 72,
            colorHex: iconColorHex
        )
    }

    private var uploadRow: some View {
        PhotosPicker(
            selection: $photoItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack(spacing: 12) {
                Image(ph: "upload-simple", weight: .fill)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.primaryText)
                Text("從相簿上傳")
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(Theme.primaryText.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cardBackground)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .formSectionHeaderStyle()
            .padding(.horizontal, 20)
    }

    private func symbolTile(_ name: String) -> some View {
        let isSelected = (iconPhName == name) && (iconImageData == nil)
        return Button {
            withAnimation {
                iconPhName = name
                iconImageData = nil
                photoItem = nil
            }
        } label: {
            Image(ph: name, weight: isSelected ? .fill : .bold)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(
                    isSelected ? Theme.iconColor(iconColorHex) : Theme.primaryText.opacity(0.5)
                )
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - State

    private var currentSourceLabel: LocalizedStringKey {
        if iconImageData != nil { return "已上傳圖片" }
        if iconPhName != nil { return "已選擇圖示" }
        return "預設（依類型）"
    }

    private func resetToDefault() {
        iconImageData = nil
        iconPhName = nil
        photoItem = nil
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: raw) else { return }
        let resized = ui.downscaled(maxDimension: 512)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }
        await MainActor.run {
            withAnimation {
                iconImageData = jpeg
                iconPhName = nil
            }
        }
    }
}

private extension UIImage {
    /// Aspect-fit downscale; never enlarges. Used to keep icon payload small
    /// before stamping into SwiftData via `@Attribute(.externalStorage)`.
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
