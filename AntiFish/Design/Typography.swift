import AppKit
import SwiftUI

/// Plus Jakarta Sans when it is bundled, the system face otherwise. Same helper Overlap uses, so
/// dropping the four .otf files into `AntiFish/Resources/Fonts` switches both apps to the same type.
enum AppFont {
    static let isPJSLoaded: Bool = {
        NSFont(name: "PlusJakartaSans-Regular", size: 12) != nil
    }()

    static func font(_ weight: Font.Weight, size: CGFloat) -> Font {
        guard isPJSLoaded else { return .system(size: size, weight: weight, design: .default) }
        let name: String = switch weight {
        case .medium: "PlusJakartaSans-Medium"
        case .semibold, .bold: "PlusJakartaSans-Bold"
        case .heavy, .black: "PlusJakartaSans-ExtraBold"
        default: "PlusJakartaSans-Regular"
        }
        return .custom(name, size: size)
    }
}

/// Overlap's type scale, trimmed to what a chat app needs.
enum AppType {
    static var display: Font { AppFont.font(.heavy, size: 56) }
    static var headingLg: Font { AppFont.font(.bold, size: 40) }
    static var heading: Font { AppFont.font(.bold, size: 32) }
    static var headingSm: Font { AppFont.font(.bold, size: 24) }
    static var title: Font { AppFont.font(.bold, size: 20) }
    static var subheading: Font { AppFont.font(.medium, size: 19) }
    static var body: Font { AppFont.font(.regular, size: 17) }
    static var bodyMedium: Font { AppFont.font(.medium, size: 17) }
    static var bodySm: Font { AppFont.font(.regular, size: 15) }
    static var bodySmMedium: Font { AppFont.font(.medium, size: 15) }
    static var caption: Font { AppFont.font(.regular, size: 13) }
    static var captionSm: Font { AppFont.font(.medium, size: 12) }
}
