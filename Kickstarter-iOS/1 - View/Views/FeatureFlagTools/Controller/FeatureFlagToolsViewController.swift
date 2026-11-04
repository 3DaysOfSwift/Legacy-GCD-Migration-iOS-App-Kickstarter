import Observation
import Foundation
import KsApi

import Prelude
import UIKit

final class FeatureFlagToolsViewController: UITableViewController {
  // MARK: - Properties

  private var features = [FeatureEnabled]()
  private let reuseId = "FeatureFlagTools.TableViewCell"
  private let viewModel = FeatureFlagToolsViewModel()

  static func instantiate() -> FeatureFlagToolsViewController {
    return FeatureFlagToolsViewController(style: .plain)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    _ = self
      |> \.title .~ "Config Feature flags"

    _ = self.tableView
      |> \.tableFooterView .~ UIView(frame: .zero)

    self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: self.reuseId)

    self.viewModel.viewDidLoad()
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onUpdateConfig = { [weak self] in self?.updateConfig(with: $0) }
    self.viewModel.onConfigUpdated = { NotificationCenter.default.post(name: .ksr_configUpdated, object: nil) }
    self.observeFeatures()
  }

  private func observeFeatures() {
    withObservationTracking {
      self.features = featureEnabledFromDictionaries(self.viewModel.reloadWithData)
      self.tableView.reloadData()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeFeatures() }
    }
  }

  @objc private func switchTogged(_ switchControl: UISwitch) {
    self.viewModel.setFeatureAtIndexEnabled(index: switchControl.tag, isEnabled: switchControl.isOn)
  }

  // MARK: - Private Helpers

  private func updateConfig(with features: Features) {
    guard let config = AppEnvironment.current.config else { return }

    let updatedConfig = config
      |> \.features .~ features

    AppEnvironment.updateDebugData(DebugData(config: updatedConfig))
    AppEnvironment.updateConfig(updatedConfig)

    self.viewModel.didUpdateConfig()
  }
}

// MARK: - UITableViewDataSource

extension FeatureFlagToolsViewController {
  override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
    return self.features.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: self.reuseId, for: indexPath)
    let (feature, enabled) = self.features[indexPath.row]

    let switchControl = UISwitch(frame: .zero)
      |> baseSwitchControlStyle
      |> \.tag .~ indexPath.row
      |> \.isOn .~ enabled

    switchControl.addTarget(self, action: #selector(self.switchTogged(_:)), for: .valueChanged)

    _ = cell
      ?|> baseTableViewCellStyle()
      ?|> \.accessoryView .~ switchControl

    _ = cell.textLabel
      ?|> baseTableViewCellTitleLabelStyle
      ?|> \.text .~ feature.description

    return cell
  }
}
