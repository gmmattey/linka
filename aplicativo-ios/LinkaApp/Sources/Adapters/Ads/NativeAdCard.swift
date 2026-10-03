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
    private let attributionLabel = UILabel()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let actionLabel = UILabel()
    private let adIconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.withAlphaComponent(0.45).cgColor

        attributionLabel.text = LinkaCopy.value("ads.native.attribution")
        attributionLabel.font = .preferredFont(forTextStyle: .caption2)
        attributionLabel.textColor = .secondaryLabel
        attributionLabel.adjustsFontForContentSizeCategory = true

        headlineLabel.font = .preferredFont(forTextStyle: .headline)
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 2
        headlineLabel.adjustsFontForContentSizeCategory = true

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        bodyLabel.adjustsFontForContentSizeCategory = true

        actionLabel.font = .preferredFont(forTextStyle: .subheadline)
        actionLabel.textColor = tintColor
        actionLabel.textAlignment = .right
        actionLabel.adjustsFontForContentSizeCategory = true
        actionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        adIconView.layer.cornerRadius = 8
        adIconView.clipsToBounds = true
        adIconView.contentMode = .scaleAspectFill

        let textStack = UIStackView(arrangedSubviews: [attributionLabel, headlineLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [adIconView, textStack, actionLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            adIconView.widthAnchor.constraint(equalToConstant: 40),
            adIconView.heightAnchor.constraint(equalToConstant: 40),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])

        headlineView = headlineLabel
        bodyView = bodyLabel
        callToActionView = actionLabel
        iconView = adIconView
        accessibilityLabel = LinkaCopy.value("ads.native.attribution")
    }

    required init?(coder: NSCoder) { nil }

    func populate(with ad: NativeAd) {
        headlineLabel.text = ad.headline
        bodyLabel.text = ad.body
        bodyLabel.isHidden = ad.body == nil
        actionLabel.text = ad.callToAction
        actionLabel.isHidden = ad.callToAction == nil
        adIconView.image = ad.icon?.image
        adIconView.isHidden = ad.icon == nil
        nativeAd = ad
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
#endif
