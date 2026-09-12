import AppKit
import SwiftUI

struct Avatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.primaryFixed)
                    Text(initials)
                        .font(AppFont.font(.bold, size: size * 0.36))
                        .foregroundStyle(Color.primaryBlue)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
