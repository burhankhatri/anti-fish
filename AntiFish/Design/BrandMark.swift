import AppKit
import SwiftUI

/// The AntiFish mark: a fish whose ribs are a waveform, which is the whole idea of the app in one
/// shape. Falls back to a symbol if the asset is missing so a view never renders empty.
struct BrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        if let image = BrandMark.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size * 0.70)
                .accessibilityLabel("AntiFish")
        } else {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: size * 0.6, weight: .light))
                .foregroundStyle(Color.primaryBlue)
        }
    }

    static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "AntiFishMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AntiFish/Resources/AntiFishMark.png")
        return NSImage(contentsOf: repo)
    }()
}
