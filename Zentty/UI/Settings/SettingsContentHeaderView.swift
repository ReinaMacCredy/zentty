import AppKit

/// The header shown at the top of the settings detail pane: the section's
/// gradient badge alongside its title and a one-line subtitle, in the style of
/// macOS System Settings / Raycast.
@MainActor
final class SettingsContentHeaderView: NSView {
    private enum Metrics {
        static let badgeDiameter: CGFloat = 28
        static let horizontalInset: CGFloat = 28
        static let topInset: CGFloat = 18
        static let bottomInset: CGFloat = 12
        static let badgeToTextSpacing: CGFloat = 12
    }

    private let badgeImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        badgeImageView.translatesAutoresizingMaskIntoConstraints = false
        badgeImageView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(badgeImageView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            badgeImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            badgeImageView.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            badgeImageView.widthAnchor.constraint(equalToConstant: Metrics.badgeDiameter),
            badgeImageView.heightAnchor.constraint(equalToConstant: Metrics.badgeDiameter),

            textStack.leadingAnchor.constraint(
                equalTo: badgeImageView.trailingAnchor,
                constant: Metrics.badgeToTextSpacing
            ),
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.topInset),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.bottomInset),
        ])
    }

    func configure(with section: SettingsSection) {
        badgeImageView.image = SettingsSidebarIconBadge.cachedImage(
            for: section,
            diameter: Metrics.badgeDiameter
        )
        titleLabel.stringValue = section.title
        let subtitle = section.subtitle
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
    }

    // MARK: - For Testing

    var titleForTesting: String {
        titleLabel.stringValue
    }

    var subtitleForTesting: String {
        subtitleLabel.stringValue
    }
}
