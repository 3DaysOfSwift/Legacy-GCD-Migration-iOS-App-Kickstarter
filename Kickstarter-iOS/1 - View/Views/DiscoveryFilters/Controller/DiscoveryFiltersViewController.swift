import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol DiscoveryFiltersViewControllerDelegate: AnyObject {
  func discoveryFilters(_ viewController: DiscoveryFiltersViewController, selectedRow: SelectableRow)
  func discoveryFiltersDidClose(_ viewController: DiscoveryFiltersViewController)
}

internal final class DiscoveryFiltersViewController: UIViewController, UITableViewDelegate {
  @IBOutlet private var bgView: UIView!
  @IBOutlet private var closeButton: UIButton!
  @IBOutlet private var filtersTableView: UITableView!

  private let dataSource = DiscoveryFiltersDataSource()
  private let viewModel: DiscoveryFiltersViewModel = DiscoveryFiltersViewModel()

  internal weak var delegate: DiscoveryFiltersViewControllerDelegate?

  internal static func configuredWith(selectedRow: SelectableRow)
    -> DiscoveryFiltersViewController {
    let vc = Storyboard.Discovery.instantiate(DiscoveryFiltersViewController.self)
    vc.viewModel.configureWith(selectedRow: selectedRow)
    return vc
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.filtersTableView.dataSource = self.dataSource
    self.filtersTableView.delegate = self

    self.closeButton.addTarget(self, action: #selector(self.closeButtonTapped), for: .touchUpInside)

    self.viewModel.viewDidLoad()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    self.viewModel.viewDidAppear()
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onAnimateIn = { [weak self] in self?.animateIn() }
    self.viewModel.onLoading = { [weak self] visible in
      guard let self else { return }
      if visible { self.dataSource.loadCategoriesLoaderRow(); self.filtersTableView.reloadData() }
      else { self.deleteCategoriesLoaderRow(self.filtersTableView) }
    }
    self.viewModel.onTopRows = { [weak self] rows, id in
      self?.dataSource.load(topRows: rows, categoryId: id); self?.filtersTableView.reloadData()
    }
    self.viewModel.onFavoriteRows = { [weak self] rows, id in
      self?.dataSource.load(favoriteRows: rows, categoryId: id); self?.filtersTableView.reloadData()
    }
    self.viewModel.onCategoryRows = { [weak self] rows, id, selected in
      self?.dataSource.load(categoryRows: rows, categoryId: id); self?.reloadCategories(selectedRowId: selected)
    }
    self.viewModel.onSelectedRow = { [weak self] row in
      guard let self else { return }
      self.animateOut(); self.delegate?.discoveryFilters(self, selectedRow: row)
    }
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self.bgView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.filtersTableView
      |> UITableView.lens.rowHeight .~ UITableView.automaticDimension
      |> UITableView.lens.estimatedRowHeight .~ 55.0
      |> UITableView.lens.backgroundColor .~ .clear

    _ = self.closeButton
      |> UIButton.lens.accessibilityLabel %~ { _ in Strings.Closes_filters() }
  }

  internal func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
    if let expandableRow = self.dataSource.expandableRow(indexPath: indexPath) {
      self.viewModel.tapped(expandableRow: expandableRow)
    } else if let selectableRow = self.dataSource.selectableRow(indexPath: indexPath) {
      self.viewModel.tapped(selectableRow: selectableRow)
    }
  }

  internal func tableView(_: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    if let cell = cell as? DiscoverySelectableRowCell {
      cell.willDisplay()
    } else if let cell = cell as? DiscoveryExpandableRowCell {
      cell.willDisplay()
    } else if let cell = cell as? DiscoveryExpandedSelectableRowCell {
      cell.willDisplay()

      if self.viewModel.shouldAnimateSelectableCell {
        let delay = indexPath.row - (self.dataSource.expandedRow() ?? 0)
        cell.animateIn(delayOffset: delay)
      }
    }
  }

  private func animateIn() {
    self.filtersTableView.frame.origin.y -= 20.0
    self.filtersTableView.alpha = 0

    UIView.animate(
      withDuration: 0.3,
      delay: 0.0,
      usingSpringWithDamping: 0.45,
      initialSpringVelocity: 1.0,
      options: .curveEaseOut,
      animations: {
        self.bgView.alpha = 1.0
        self.filtersTableView.alpha = 1.0
        self.filtersTableView.frame.origin.y += 20.0
      },
      completion: nil
    )
  }

  private func animateOut() {
    UIView.animate(
      withDuration: 0.2,
      delay: 0.0,
      options: .curveEaseIn,
      animations: {
        self.filtersTableView.alpha = 0.0
        self.filtersTableView.frame.origin.y -= 20.0
      },
      completion: nil
    )

    UIView.animate(
      withDuration: 0.3,
      delay: 0.1,
      options: .curveEaseOut,
      animations: {
        self.bgView.alpha = 0.0
      },
      completion: nil
    )
  }

  @objc private func closeButtonTapped(_: UIButton) {
    self.animateOut()
    self.delegate?.discoveryFiltersDidClose(self)
  }

  private func reloadCategories(selectedRowId: Int?) {
    if let indexPath = self.dataSource.indexPath(forCategoryId: selectedRowId) {
      self.filtersTableView.reloadData()
      self.filtersTableView.scrollToRow(at: indexPath as IndexPath, at: .top, animated: false)
    } else {
      UIView.transition(
        with: self.filtersTableView,
        duration: 0.2,
        options: .transitionCrossDissolve,
        animations: {
          self.filtersTableView.reloadData()
        },
        completion: nil
      )
    }
  }

  private func deleteCategoriesLoaderRow(_ tableView: UITableView) {
    guard let
      deleteCategoriesLoaderRow = self.dataSource.deleteCategoriesLoaderRow(tableView),
      !deleteCategoriesLoaderRow.isEmpty else {
      return
    }

    self.filtersTableView.beginUpdates()
    defer { self.filtersTableView.endUpdates() }

    self.filtersTableView.deleteRows(at: deleteCategoriesLoaderRow, with: .fade)
  }
}
