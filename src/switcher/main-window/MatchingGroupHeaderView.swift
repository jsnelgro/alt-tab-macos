import Cocoa

/// The name above a matching-group section in the Titles list. Not an entry of `Windows.list`: selection,
/// hover and every window action index into that list, so headers live beside the tiles instead.
///
/// The name is a `CATextLayer`, not an `NSTextField`. Inside the tiles' document view a label added this
/// way never drew: logged live, its `needsDisplay` was back to false within the same layout and its layer
/// never got contents, while the space for it was laid out. A text layer renders when its properties are
/// set, without AppKit's display pass.
class MatchingGroupHeaderView: FlippedView {
    private let textLayer = CATextLayer()

    static var font: NSFont { NSFont.systemFont(ofSize: (Appearance.fontHeight * 0.85).rounded(), weight: .semibold) }

    /// Derived from `Appearance.fontColor` like the tile titles', so it follows the switcher's theme.
    private static var textColor: NSColor { Appearance.fontColor.withAlphaComponent(0.55) }

    /// The text's line height plus breathing room above it, so a section reads as separate from the one before.
    static func height() -> CGFloat {
        lineHeight(font) + 6
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        textLayer.truncationMode = .end
        textLayer.isWrapped = false
        textLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "string": NSNull(),
                             "foregroundColor": NSNull(), "fontSize": NSNull()]
        layer!.addSublayer(textLayer)
    }

    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

    func update(_ name: String) {
        let font = Self.font
        textLayer.font = font
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = Self.textColor.cgColor
        textLayer.alignmentMode = App.shared.userInterfaceLayoutDirection == .leftToRight ? .left : .right
        textLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        textLayer.string = name.uppercased(with: .current)
        layoutText()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutText()
    }

    /// Bottom-aligned, so the extra height in `height()` becomes space above the name. AppKit keeps a
    /// view's sublayers in the view's own coordinates, so y grows downward here as it does for the view.
    private func layoutText() {
        let height = Self.lineHeight(Self.font)
        textLayer.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
    }

    /// Hover, clicks and drops belong to the tiles.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
