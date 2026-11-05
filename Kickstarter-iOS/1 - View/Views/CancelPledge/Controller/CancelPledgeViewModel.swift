import KsApi
import Prelude
import UIKit

public struct CancelPledgeViewData {
  public let project: Project // TODO: remove once tracking is updated.
  public let projectName: String
  public let omitUSCurrencyCode: Bool
  public let backingId: String
  public let pledgeAmount: Double
}

@MainActor
final class CancelPledgeViewModel {
  enum Event {
    case details(NSAttributedString)
    case buttonEnabled(Bool)
    case error(String)
    case loading(Bool)
    case success(String)
  }

  var onEvent: ((Event) -> Void)?
  private let feature: PledgeFeature
  private var data: CancelPledgeViewData?
  private var hasLoaded = false
  private var reason: String?
  private var task: Task<Void, Never>?

  init(feature: PledgeFeature = AppModel.shared.pledgeFeature) {
    self.feature = feature
  }

  func configure(with data: CancelPledgeViewData) {
    self.data = data
    self.publishDetailsIfReady()
  }

  func viewDidLoad() {
    self.hasLoaded = true
    self.reason = nil
    self.publishDetailsIfReady()
  }

  func traitCollectionDidChange() {
    self.publishDetailsIfReady(enableButton: false)
  }

  func textFieldDidEndEditing(with text: String?) { self.reason = text }

  func cancelPledgeButtonTapped() {
    guard self.hasLoaded, let data = self.data else { return }
    self.task?.cancel()
    self.onEvent?(.loading(true))
    self.onEvent?(.buttonEnabled(false))
    let input = CancelBackingInput(backingId: data.backingId, cancellationReason: self.reason)
    let feature = self.feature
    self.task = Task { [weak self] in
      do {
        try await feature.cancelWithPresentationDelay(input)
        guard !Task.isCancelled, let self else { return }
        self.onEvent?(.success(Strings.Youve_canceled_your_pledge()))
        self.onEvent?(.loading(false))
        self.onEvent?(.buttonEnabled(true))
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), let self else { return }
        self.onEvent?(.error((error as? ErrorEnvelope)?.localizedDescription ?? error.localizedDescription))
        self.onEvent?(.loading(false))
        self.onEvent?(.buttonEnabled(true))
      }
    }
  }

  func waitForOperation() async { await self.task?.value }

  deinit { self.task?.cancel() }

  private func publishDetailsIfReady(enableButton: Bool = true) {
    guard self.hasLoaded, let data = self.data else { return }
    let amount = Format.currency(
      data.pledgeAmount,
      currencyCode: data.project.statsCurrency,
      omitCurrencyCode: data.omitUSCurrencyCode
    )
    self.onEvent?(.details(createCancellationDetailsAttributedText(with: amount, projectName: data.projectName)))
    if enableButton { self.onEvent?(.buttonEnabled(true)) }
  }
}

private func createCancellationDetailsAttributedText(with amount: String, projectName: String)
  -> NSAttributedString {
  let fullString = Strings
    .Are_you_sure_you_wish_to_cancel_your_amount_pledge_to_project_name(
      amount: amount,
      project_name: projectName
    )
  let attributedString: NSMutableAttributedString = NSMutableAttributedString.init(string: fullString)
  let regularFontAttribute = [NSAttributedString.Key.font: UIFont.ksr_callout()]
  let boldFontAttribute = [NSAttributedString.Key.font: UIFont.ksr_callout().bolded]
  let fullRange = (fullString as NSString).localizedStandardRange(of: fullString)
  let rangeAmount: NSRange = (fullString as NSString).localizedStandardRange(of: amount)
  let rangeProjectName: NSRange = (fullString as NSString).localizedStandardRange(of: projectName)

  attributedString.addAttributes(regularFontAttribute, range: fullRange)
  attributedString.addAttributes(boldFontAttribute, range: rangeAmount)
  attributedString.addAttributes(boldFontAttribute, range: rangeProjectName)

  return attributedString
}
