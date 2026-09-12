import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    // Palette carried over from Overlap so the two apps look like siblings.

    // Primary — deep cobalt
    static let primaryBlue          = Color(hex: 0x004BBC)
    static let primaryContainer     = Color(hex: 0x0061EF)
    static let primaryFixed         = Color(hex: 0xDAE2FF)
    static let primaryFixedDim      = Color(hex: 0xB2C5FF)
    static let onPrimary            = Color(hex: 0xFFFFFF)

    // Secondary — mustard
    static let secondaryMustard     = Color(hex: 0x735C00)
    static let secondaryContainer   = Color(hex: 0xFDCC00)
    static let secondaryFixed       = Color(hex: 0xFFE086)
    static let onSecondaryFixed     = Color(hex: 0x231A00)

    // Tertiary — purple
    static let tertiaryPurple       = Color(hex: 0x5E40A3)
    static let tertiaryFixed        = Color(hex: 0xE9DDFF)

    // Surface / background — warm neutral
    static let background                = Color(hex: 0xFAF9FA)
    static let surfaceContainerLowest    = Color(hex: 0xFFFFFF)
    static let surfaceContainerLow       = Color(hex: 0xF4F3F4)
    static let surfaceContainer          = Color(hex: 0xEEEDEE)
    static let surfaceContainerHigh      = Color(hex: 0xE9E8E9)
    static let surfaceContainerHighest   = Color(hex: 0xE3E2E3)
    static let surfaceDim                = Color(hex: 0xDADADB)

    // Outline
    static let outlineColor              = Color(hex: 0x737687)
    static let outlineVariant            = Color(hex: 0xC2C6D8)

    // Foregrounds
    static let onSurface                 = Color(hex: 0x1A1C1D)
    static let onSurfaceVariant          = Color(hex: 0x424655)

    // Error
    static let errorRed                  = Color(hex: 0xBA1A1A)
    static let errorContainer            = Color(hex: 0xFFDAD6)
    static let onErrorContainer          = Color(hex: 0x93000A)

    // Success
    static let successGreen              = Color(hex: 0x1F7A2E)
    static let successContainer          = Color(hex: 0xD7F5DD)
    static let onSuccessContainer        = Color(hex: 0x0F4A1B)

    // Caution — AntiFish's own, for a voice that matches someone on an unsaved number.
    static let cautionAmber              = Color(hex: 0x8A5A00)
    static let cautionContainer          = Color(hex: 0xFFE8C2)
    static let onCautionContainer        = Color(hex: 0x5A3A00)
}
