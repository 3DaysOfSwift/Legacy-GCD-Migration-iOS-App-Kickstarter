import Library
import Prelude
import SwiftUI
import UIKit

internal final class ReportProjectCell: UITableViewCell, ValueCell {
  private var reportHost: UIHostingController<ReportProjectLabelView>?
  private var leadingInset: NSLayoutConstraint?
  private var trailingInset: NSLayoutConstraint?

  internal func configureWith(value projectFlagged: Bool) {
    self.setupTableViewCellStyle(projectFlagged: projectFlagged)
    self.setupReportProjectLabelView(projectFlagged: projectFlagged)
  }

  internal override func bindStyles() {
    super.bindStyles()

    self.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: .greatestFiniteMagnitude)
    self.setNeedsLayout()
  }

  // MARK: - Private Methods

  private func setupTableViewCellStyle(projectFlagged: Bool) {
    let isAccessibilityElement = projectFlagged ? false : true
    let accessibilityLabel = projectFlagged ? Strings.Report_this_project_to() : ""
    let accessibilityTraits = projectFlagged
      ? UIAccessibilityTraits.staticText
      : UIAccessibilityTraits.button

    _ = self
      |> baseTableViewCellStyle()
      |> ReportProjectCell.lens.accessibilityTraits .~ accessibilityTraits
      |> ReportProjectCell.lens.isAccessibilityElement .~ isAccessibilityElement
      |> ReportProjectCell.lens.accessibilityLabel .~ accessibilityLabel
  }

  private func setupReportProjectLabelView(projectFlagged: Bool) {
    let inset = self.traitCollection.isRegularRegular ? Styles.grid(16) : Styles.gridHalf(5)
    if let host = self.reportHost {
      self.leadingInset?.constant = inset
      self.trailingInset?.constant = -inset
      host.rootView = ReportProjectLabelView(flagged: projectFlagged)
      return
    }
    let hostingController =
      UIHostingController(rootView: ReportProjectLabelView(flagged: projectFlagged))

    self.reportHost = hostingController
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    hostingController.view.backgroundColor = .clear

    self.contentView.addSubview(hostingController.view)

    let leading = hostingController.view.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: inset)
    let trailing = hostingController.view.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -inset)
    self.leadingInset = leading
    self.trailingInset = trailing

    NSLayoutConstraint.activate([
      hostingController.view.topAnchor
        .constraint(equalTo: self.contentView.topAnchor, constant: Styles.gridHalf(5)),
      hostingController.view.bottomAnchor
        .constraint(equalTo: self.contentView.bottomAnchor, constant: -Styles.gridHalf(5)),
      leading, trailing
    ])
  }
}
