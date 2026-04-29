import CoreGraphics

/// Corner-radius scale. Tahoe defaults trend toward `lg` (14pt) for windows
/// and `md` (10pt) for inset cards. `pill` is sentinel for fully rounded shapes.
enum BobRadii {
    /// Sentinel — caller treats as `Capsule()` shape.
    static let pill: CGFloat = .infinity
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 22
}
