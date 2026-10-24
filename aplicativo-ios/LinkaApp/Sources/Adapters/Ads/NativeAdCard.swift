#if os(iOS)
import SwiftUI
import UIKit
import GoogleMobileAds

/// Ponte UIKit exigida pela API native do Google. Os assets são registrados no
/// `NativeAdView`, para que o SDK controle interação e atribuição corretamente.
struct NativeAdCard: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> LinkaNativeAdView {
        LinkaNativeAdView()
    }

    func updateUIView(_ view: LinkaNativeAdView, context: Context) {
        view.populate(with: nativeAd)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: LinkaNativeAdView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        uiView.bounds.size = CGSize(width: width, height: 0)
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        let fittingSize = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fittingSize.height)
    }
}

final class LinkaNativeAdView: NativeAdView {
    private let attributionLabel = PaddedLabel()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let adIconView = UIImageView()
    private let contentRow = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.withAlphaComponent(0.45).cgColor
        layoutMargins = .init(top: 14, left: 16, bottom: 14, right: 16)

        attributionLabel.text = LinkaCopy.value("ads.native.attribution")
        attributionLabel.font = .preferredFont(forTextStyle: .caption2)
        attributionLabel.textColor = .tertiaryLabel
        attributionLabel.backgroundColor = .tertiarySystemFill
        attributionLabel.layer.cornerRadius = 5
        attributionLabel.layer.cornerCurve = .continuous
        attributionLabel.clipsToBounds = true
        attributionLabel.textAlignment = .center
        attributionLabel.textInsets = .init(top: 3, left: 6, bottom: 3, right: 6)
        attributionLabel.adjustsFontForContentSizeCategory = true
        attributionLabel.setContentHuggingPriority(.required, for: .horizontal)

        headlineLabel.font = .preferredFont(forTextStyle: .headline)
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 2
        headlineLabel.adjustsFontForContentSizeCategory = true

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        bodyLabel.adjustsFontForContentSizeCategory = true

        var actionConfiguration = UIButton.Configuration.tinted()
        actionConfiguration.baseForegroundColor = .white
        actionConfiguration.baseBackgroundColor = UIColor(Color.brandSurface)
        actionConfiguration.cornerStyle = .medium
        actionConfiguration.contentInsets = .init(top: 8, leading: 14, bottom: 8, trailing: 14)
        actionButton.configuration = actionConfiguration
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        // O SDK recebe o botão como asset, mas controla o toque pelo
        // NativeAdView; não transformamos o CTA em uma ação própria do app.
        actionButton.isUserInteractionEnabled = false
        actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        adIconView.layer.cornerRadius = 8
        adIconView.layer.cornerCurve = .continuous
        adIconView.clipsToBounds = true
        adIconView.contentMode = .scaleAspectFill
        adIconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        adIconView.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let textStack = UIStackView(arrangedSubviews: [headlineLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        contentRow.addArrangedSubview(adIconView)
        contentRow.addArrangedSubview(textStack)
        contentRow.addArrangedSubview(actionButton)
        contentRow.axis = .horizontal
        contentRow.alignment = .center
        contentRow.spacing = 12

        let contentStack = UIStackView(arrangedSubviews: [attributionLabel, contentRow])
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])

        headlineView = headlineLabel
        bodyView = bodyLabel
        callToActionView = actionButton
        iconView = adIconView
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = LinkaCopy.value("ads.native.accessibility.hint")
    }

    required init?(coder: NSCoder) { nil }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let usesAccessibilitySize = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        contentRow.axis = usesAccessibilitySize ? .vertical : .horizontal
        contentRow.alignment = usesAccessibilitySize ? .leading : .center
        actionButton.contentHorizontalAlignment = usesAccessibilitySize ? .leading : .center
    }

    func populate(with ad: NativeAd) {
        headlineLabel.text = ad.headline
        bodyLabel.text = ad.body
        bodyLabel.isHidden = ad.body == nil
        actionButton.setTitle(ad.callToAction, for: .normal)
        actionButton.isHidden = ad.callToAction == nil
        adIconView.image = ad.icon?.image
        adIconView.isHidden = ad.icon == nil
        accessibilityLabel = [
            LinkaCopy.value("ads.native.attribution"),
            ad.headline,
            ad.body,
            ad.callToAction
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: ". ")
        nativeAd = ad
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

private final class PaddedLabel: UILabel {
    var textInsets = UIEdgeInsets.zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return .init(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }
}
#endif
