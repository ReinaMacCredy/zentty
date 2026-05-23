import AppKit

/// A sidebar row: a colored gradient icon badge followed by the section title.
/// The title is wired as the cell's `textField`, while the custom row view
/// keeps selected text in the normal background style.
@MainActor
final class SettingsSidebarRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("settings.sidebar.row")
    static let badgeDiameter: CGFloat = 20

    private let badgeImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        identifier = Self.reuseIdentifier

        badgeImageView.translatesAutoresizingMaskIntoConstraints = false
        badgeImageView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(badgeImageView)
        addSubview(titleLabel)
        imageView = badgeImageView
        textField = titleLabel

        NSLayoutConstraint.activate([
            // Sit just inside the row highlight's gutter — a small, tight left
            // padding for the icon (the highlight rect itself is unaffected).
            badgeImageView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: SettingsSidebarViewController.contentHorizontalInset + 2
            ),
            badgeImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeImageView.widthAnchor.constraint(equalToConstant: Self.badgeDiameter),
            badgeImageView.heightAnchor.constraint(equalToConstant: Self.badgeDiameter),

            titleLabel.leadingAnchor.constraint(equalTo: badgeImageView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    func configure(with section: SettingsSection) {
        badgeImageView.image = SettingsSidebarIconBadge.cachedImage(
            for: section,
            diameter: Self.badgeDiameter
        )
        titleLabel.stringValue = section.title
    }

    // MARK: - For Testing

    var badgeImageForTesting: NSImage? {
        badgeImageView.image
    }

    var titleForTesting: String {
        titleLabel.stringValue
    }
}
