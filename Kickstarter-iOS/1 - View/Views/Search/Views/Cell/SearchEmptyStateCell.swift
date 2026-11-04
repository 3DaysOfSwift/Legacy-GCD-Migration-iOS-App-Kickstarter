import KDS
import KsApi

import Prelude
import UIKit

@MainActor
protocol SearchEmptyStateCellDelegate: AnyObject {
  func searchEmptyStateCellDidTapRemoveAllFiltersButton(
    _ cell: SearchEmptyStateCell
  )
}

internal final class SearchEmptyStateCell: UITableViewCell, ValueCell {
  typealias Value = SearchEmptyStateSearchData

  fileprivate let viewModel = SearchEmptyStateCellViewModel()

  weak var delegate: SearchEmptyStateCellDelegate?

  private var titleLabel: UILabel = UILabel()
  private var subtitleLabel: UILabel = UILabel()
  private var clearFiltersButton: KSRButton
  private var rootStackView: UIStackView = UIStackView()

  internal func configureWith(value: SearchEmptyStateSearchData) {
    self.viewModel.configureWith(data: value)
    self.titleLabel.text = self.viewModel.titleText
    self.subtitleLabel.text = self.viewModel.subtitleText
    self.clearFiltersButton.isHidden = self.viewModel.hideClearFiltersButton
  }

  override init(
    style: UITableViewCell.CellStyle,
    reuseIdentifier: String?
  ) {
    self.clearFiltersButton = KSRButton(style: .filled)

    super.init(style: style, reuseIdentifier: reuseIdentifier)

    self.setupViews()
    self.bindStyles()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  internal override func bindStyles() {
    super.bindStyles()

    self.selectionStyle = .none

    self.backgroundColor = .clear
    self.contentView.layoutMargins = self.traitCollection.isRegularRegular
      ? .init(top: Styles.grid(4), left: Styles.grid(24), bottom: Styles.grid(2), right: Styles.grid(24))
      : .init(topBottom: Styles.grid(6), leftRight: Styles.grid(4))

    self.rootStackView.axis = .vertical
    self.rootStackView.alignment = .center
    self.rootStackView.spacing = Styles.grid(3)

    self.titleLabel.textColor = Colors.Text.primary.uiColor()
    self.titleLabel.font = InterFont.headingXL.font()
    self.titleLabel.textAlignment = .center
    self.titleLabel.numberOfLines = 3

    self.subtitleLabel.textColor = Colors.Text.secondary.uiColor()
    self.subtitleLabel.font = InterFont.bodyMD.font()
    self.subtitleLabel.textAlignment = .center
    self.subtitleLabel.numberOfLines = 0
  }

  private func setupViews() {
    self.contentView.addSubview(self.rootStackView)

    self.rootStackView.addArrangedSubviews(self.titleLabel, self.subtitleLabel, self.clearFiltersButton)
    self.rootStackView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      self.rootStackView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor),
      self.rootStackView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor),
      self.rootStackView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
      self.rootStackView.trailingAnchor
        .constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor)
    ])

    self.clearFiltersButton.setTitle(Strings.Remove_all_filters(), for: .normal)
    self.clearFiltersButton.addTarget(self, action: #selector(self.onClearFiltersTapped), for: .touchUpInside)
    self.clearFiltersButton.translatesAutoresizingMaskIntoConstraints = false

    self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
  }

  @objc private func onClearFiltersTapped() {
    self.delegate?.searchEmptyStateCellDidTapRemoveAllFiltersButton(self)
  }
}
