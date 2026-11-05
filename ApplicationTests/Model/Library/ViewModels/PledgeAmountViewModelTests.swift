@testable import Kickstarter_iOS
import KDS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class PledgeAmountViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = PledgeAmountViewModel()

  private let amountIsValid = AmountRecording<Bool>()
  private let amountMax = AmountRecording<Double>()
  private let amountMin = AmountRecording<Double>()
  private let amountValue = AmountRecording<Double>()
  private let currency = AmountRecording<String>()
  private let doneButtonIsEnabled = AmountRecording<Bool>()
  private let generateSelectionFeedback = AmountRecording<Void>()
  private let generateNotificationWarningFeedback = AmountRecording<Void>()
  private let labelTextColor = AmountRecording<UIColor>()
  private let maxPledgeAmountErrorLabelIsHidden = AmountRecording<Bool>()
  private let maxPledgeAmountErrorLabelText = AmountRecording<String>()
  private let plusSignLabelHidden = AmountRecording<Bool>()
  private let stepperMaxValue = AmountRecording<Double>()
  private let stepperMinValue = AmountRecording<Double>()
  private let stepperValue = AmountRecording<Double>()
  private let subTitleLabelHidden = AmountRecording<Bool>()
  private let textFieldIsFirstResponder = AmountRecording<Bool>()
  private let textFieldTextColor = AmountRecording<UIColor?>()
  private let textFieldValue = AmountRecording<String>()
  private let titleLabelText = AmountRecording<String>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .currency(value): self.currency.append(value)
      case let .valid(value): self.doneButtonIsEnabled.append(value)
      case .selectionFeedback: self.generateSelectionFeedback.append(())
      case .warningFeedback: self.generateNotificationWarningFeedback.append(())
      case let .color(value):
        self.labelTextColor.append(value)
        self.textFieldTextColor.append(value)
      case let .maxErrorHidden(value): self.maxPledgeAmountErrorLabelIsHidden.append(value)
      case let .maxErrorText(value): self.maxPledgeAmountErrorLabelText.append(value)
      case let .amount(value):
        self.amountIsValid.append(value.isValid)
        self.amountMax.append(value.max)
        self.amountMin.append(value.min)
        self.amountValue.append(value.amount)
      case let .noReward(value):
        self.plusSignLabelHidden.append(value)
        self.subTitleLabelHidden.append(value)
      case let .stepperMax(value): self.stepperMaxValue.append(value)
      case let .stepperMin(value): self.stepperMinValue.append(value)
      case let .stepperValue(value): self.stepperValue.append(value)
      case .endEditing: self.textFieldIsFirstResponder.append(false)
      case let .text(value): self.textFieldValue.append(value)
      case let .title(value): self.titleLabelText.append(value)
      }
    }
  }

  func testAmountCurrencyAndStepper_FromBacking() {
    let reward = Reward.postcards
      |> Reward.lens.minimum .~ 6

    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ reward
          |> Backing.lens.rewardId .~ reward.id
          |> Backing.lens.shippingAmount .~ 10
          |> Backing.lens.amount .~ 700.0
      )

    self.vm.configureWith(data: (project, reward: Reward.postcards, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValues([0])
    self.currency.assertValues(["$"])
    self.stepperMinValue.assertValue(0)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([0])
    self.textFieldValue.assertValues(["0"])
  }

  func testAmountMax_WhenShippingAmountUpdates() {
    self.vm.configureWith(data: (.template, reward: Reward.postcards, 0))

    self.amountMax.assertValues([10_000])

    self.vm.unavailableAmountChanged(to: 20)

    self.amountMax.assertValues([10_000, 9_980])
  }

  func testAmountCurrencyAndStepper_FromBacking_DifferentReward() {
    let otherReward = Reward.otherReward
      |> Reward.lens.minimum .~ 60

    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ Reward.postcards
          |> Backing.lens.rewardId .~ Reward.postcards.id
          |> Backing.lens.shippingAmount .~ 10
          |> Backing.lens.amount .~ 700.0
      )

    self.vm.configureWith(data: (project, reward: otherReward, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValues([00])
    self.currency.assertValues(["$"])
    self.stepperMinValue.assertValue(0)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([0])
    self.textFieldValue.assertValues(["0"])
  }

  func testAmountCurrencyAndStepper_FromBacking_NoReward() {
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ nil
          |> Backing.lens.rewardId .~ nil
          |> Backing.lens.shippingAmount .~ 0
          |> Backing.lens.amount .~ 5.0
      )

    let noReward = Reward.noReward
      |> Reward.lens.minimum .~ 1

    self.vm.configureWith(data: (project, reward: noReward, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([1])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValues([1])
    self.currency.assertValues(["$"])
    self.stepperMinValue.assertValue(1)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([1])
    self.textFieldValue.assertValues(["1"])
  }

  func testAmountCurrencyAndStepper_NoReward() {
    let reward = Reward.noReward
      |> Reward.lens.minimum .~ 1
    self.vm.configureWith(data: (.template, reward: reward, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([1])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValues([1])
    self.currency.assertValues(["$"])
    self.stepperMinValue.assertValue(1)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([1])
    self.textFieldValue.assertValues(["1"])
  }

  func testAmountCurrencyAndStepper_Currency_Not_Country_HasMinMax_NoReward() {
    let reward = Reward.noReward
      |> Reward.lens.minimum .~ 1
    let project = Project.template
      |> Project.lens.country .~ Project.Country.us
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode

    self.vm.configureWith(data: (project, reward: reward, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([10])
    self.amountMax.assertValues([200_000])
    self.amountValue.assertValues([10])
    self.currency.assertValues(["MX$"])
    self.stepperMinValue.assertValue(10)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([10])
    self.textFieldValue.assertValues(["10"])
  }

  func testAmountCurrencyAndStepper_Country_DoesNotHaveMinMax_NoReward() {
    let countryWithNilMiniumPledge = Project.Country.us
      |> Project.Country.lens.minPledge .~ nil

    let launchedCountries = LaunchedCountries(countries: [countryWithNilMiniumPledge])

    withEnvironment(launchedCountries: launchedCountries) {
      let country = Project.Country.us
        |> Project.Country.lens.minPledge .~ nil

      let project = Project.template
        |> Project.lens.stats.projectCurrency .~ country.currencyCode
        |> Project.lens.country .~ country

      let reward = Reward.noReward
        |> Reward.lens.minimum .~ 1

      self.vm.configureWith(data: (project, reward: reward, 0))

      self.amountIsValid.assertValues([true])
      self.amountMin.assertValues([1])
      self.amountMax.assertValues([10_000])
      self.amountValue.assertValues([1])
      self.currency.assertValues(["$"])
      self.stepperMinValue.assertValue(1)
      self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
      self.stepperValue.assertValues([1])
      self.textFieldValue.assertValues(["1"])
    }
  }

  func testAmountCurrencyAndStepper_Reward_Minimum_Template() {
    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValues([0])
    self.currency.assertValues(["$"])
    self.stepperMinValue.assertValue(0)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([0])
    self.textFieldValue.assertValues(["0"])
  }

  func testAmountCurrencyAndStepper_Reward_Minimum_Custom() {
    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ Project.Country.jp.currencyCode

    let reward = Reward.template
      |> Reward.lens.minimum .~ 200

    self.vm.configureWith(data: (project, reward: reward, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([1_200_000])
    self.amountValue.assertValues([0])
    self.currency.assertValues(["¥"])
    self.stepperMinValue.assertValue(0)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([0])
    self.textFieldValue.assertValues(["0"])
  }

  func testDoneButtonIsEnabled_WithMaxAmount_WhenShippingAmountUpdates() {
    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.amountMax.assertValues([10_000])

    self.vm.textFieldDidEndEditing("10000")

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.unavailableAmountChanged(to: 10)

    self.amountMax.assertValues([10_000, 10_000, 9_990])
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.unavailableAmountChanged(to: 0)

    self.amountMax.assertValues([10_000, 10_000, 9_990, 10_000])
    self.doneButtonIsEnabled.assertValues([true, false, true])
  }

  func testDoneButtonIsEnabled_Stepper_NoReward() {
    self.vm.configureWith(data: (.template, reward: Reward.noReward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(2)
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(100_000)
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.stepperValueChanged(10_000)
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.stepperValueChanged(0)
    self.doneButtonIsEnabled.assertValues([true, false, true, false])

    self.vm.stepperValueChanged(1)
    self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
  }

  func testDoneButtonIsEnabled_Stepper_ProjectCurrency_HasMinMax_NoReward() {
    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ Project.Country.hk.currencyCode

    self.vm.configureWith(data: (project, reward: Reward.noReward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(11)
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(100_000)
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.stepperValueChanged(75_000)
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.stepperValueChanged(9)
    self.doneButtonIsEnabled.assertValues([true, false, true, false])

    self.vm.stepperValueChanged(10)
    self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
  }

  func testDoneButtonIsEnabled_Stepper_ProjectCurrencyCountry_DoesNotHaveMinMax_NoReward() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ country.currencyCode

    let launchedCountries = LaunchedCountries(countries: [country])

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: Reward.noReward, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(2)
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(100_000)
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.stepperValueChanged(10_000)
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.stepperValueChanged(0)
      self.doneButtonIsEnabled.assertValues([true, false, true, false])

      self.vm.stepperValueChanged(1)
      self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
    }
  }

  func testDoneButtonIsEnabled_Stepper_ProjectCurrencyCountry_HasMinMax_Reward_Minimum_Template() {
    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(11)
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(100_000)
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.stepperValueChanged(10_000)
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.stepperValueChanged(10_001)
    self.doneButtonIsEnabled.assertValues([true, false, true, false])

    self.vm.stepperValueChanged(0)
    self.doneButtonIsEnabled.assertValues([true, false, true, false, true])

    self.vm.stepperValueChanged(11)
    self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
  }

  func testDoneButtonIsEnabled_Stepper_ProjectCurrencyCountry_HasMinMax_Reward_Minimum_Custom() {
    let reward = Reward.template
      |> Reward.lens.minimum .~ 200

    self.vm.configureWith(data: (.template, reward: reward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(300)
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(100_000)
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.stepperValueChanged(10_000)
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.stepperValueChanged(100)
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.stepperValueChanged(200)
    self.doneButtonIsEnabled.assertValues([true, false, true])
  }

  func testDoneButtonIsEnabled_Stepper_ProjectCountryCurrency_DoesNotHaveMinMax_Reward_Minimum_Template() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ country.currencyCode

    let launchedCountries = LaunchedCountries(countries: [country])

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: .template, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(11)
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(100_000)
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.stepperValueChanged(10_000)
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.stepperValueChanged(0)
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.stepperValueChanged(10)
      self.doneButtonIsEnabled.assertValues([true, false, true])
    }
  }

  func testDoneButtonIsEnabled_Stepper_ProjectCountryCurrency_DoesNotHaveMinMax_Reward_Minimum_Custom() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ country.currencyCode

    let launchedCountries = LaunchedCountries(countries: [country])

    let reward = Reward.template
      |> Reward.lens.minimum .~ 200

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: reward, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(300)
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(100_000)
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.stepperValueChanged(10_000)
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.stepperValueChanged(0)
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.stepperValueChanged(200)
      self.doneButtonIsEnabled.assertValues([true, false, true])
    }
  }

  func testDoneButtonIsEnabled_TextField_NoReward() {
    self.vm.configureWith(data: (.template, reward: Reward.noReward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("2")
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("100000")
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.textFieldValueChanged("10000")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("0")
    self.doneButtonIsEnabled.assertValues([true, false, true, false])

    self.vm.textFieldValueChanged("1")
    self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
  }

  func testDoneButtonIsEnabled_TextField_ProjectCountryCurrency_HasMinMax_NoReward() {
    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ Project.Country.hk.currencyCode

    self.vm.configureWith(data: (project, reward: Reward.noReward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("11")
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("100000")
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.textFieldValueChanged("75000")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("9")
    self.doneButtonIsEnabled.assertValues([true, false, true, false])

    self.vm.textFieldValueChanged("10")
    self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
  }

  func testDoneButtonIsEnabled_TextField_ProjectCurrencyCountry_DoesNotHaveMinMax_NoReward() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ country.currencyCode

    let launchedCountries = LaunchedCountries(countries: [country])

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: Reward.noReward, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("2")
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("100000")
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.textFieldValueChanged("10000")
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.textFieldValueChanged("0")
      self.doneButtonIsEnabled.assertValues([true, false, true, false])

      self.vm.textFieldValueChanged("1")
      self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
    }
  }

  func testDoneButtonIsEnabled_TextField_ProjectCurrencyCountry_HasMinMax_Reward_Minimum_Template() {
    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("11")
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("100000")
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.textFieldValueChanged("10000")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("0")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("11")
    self.doneButtonIsEnabled.assertValues([true, false, true])
  }

  func testDoneButtonIsEnabled_TextField_ProjectCurrencyCountry_HasMinMax_Reward_Minimum_Custom() {
    let reward = Reward.template
      |> Reward.lens.minimum .~ 200

    self.vm.configureWith(data: (.template, reward: reward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("300")
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("100000")
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.textFieldValueChanged("10000")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("100")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("200")
    self.doneButtonIsEnabled.assertValues([true, false, true])
  }

  func testDoneButtonIsEnabled_TextField_ProjectCurrencyCountry_DoesNotHaveMinMax_Reward_Minimum_Template() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ country.currencyCode

    let launchedCountries = LaunchedCountries(countries: [country])

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: .template, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("11")
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("100000")
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.textFieldValueChanged("10000")
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.textFieldValueChanged("0")
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.textFieldValueChanged("10")
      self.doneButtonIsEnabled.assertValues([true, false, true])
    }
  }

  func testDoneButtonIsEnabled_TextField_ProjectCurrencyCountry_DoesNotHaveMinMax_Reward_Minimum_Custom() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ country.currencyCode

    let reward = Reward.template
      |> Reward.lens.minimum .~ 200

    let launchedCountries = LaunchedCountries(countries: [country])

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: reward, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("300")
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("100000")
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.textFieldValueChanged("10000")
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.textFieldValueChanged("0")
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.textFieldValueChanged("200")
      self.doneButtonIsEnabled.assertValues([true, false, true])
    }
  }

  func testDoneButtonIsEnabled_Combined_NoReward() {
    self.vm.configureWith(data: (.template, reward: Reward.noReward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("2")
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(100_000)
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.textFieldValueChanged("10000")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.stepperValueChanged(0)
    self.doneButtonIsEnabled.assertValues([true, false, true, false])

    self.vm.textFieldValueChanged("1")
    self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
  }

  func testDoneButtonIsEnabled_Combined_ProjectCountryCurrency_HasMinMax_NoReward() {
    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ Project.Country.hk.currencyCode

    self.vm.configureWith(data: (project, reward: Reward.noReward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(11)
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("100000")
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.stepperValueChanged(75_000)
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("9")
    self.doneButtonIsEnabled.assertValues([true, false, true, false])

    self.vm.stepperValueChanged(10)
    self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
  }

  func testDoneButtonIsEnabled_Combined_ProjectCurrencyCountry_DoesNotHaveMinMax_NoReward() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ country.currencyCode

    let launchedCountries = LaunchedCountries(countries: [country])

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: Reward.noReward, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("2")
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(100_000)
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.textFieldValueChanged("10000")
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.stepperValueChanged(0)
      self.doneButtonIsEnabled.assertValues([true, false, true, false])

      self.vm.textFieldValueChanged("1")
      self.doneButtonIsEnabled.assertValues([true, false, true, false, true])
    }
  }

  func testDoneButtonIsEnabled_Combined_ProjectCurrencyCountry_HasMinMax_Reward_Minimum_Template() {
    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(11)
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("100000")
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.stepperValueChanged(10_000)
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("0")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.stepperValueChanged(11)
    self.doneButtonIsEnabled.assertValues([true, false, true])
  }

  func testDoneButtonIsEnabled_Combined_ProjectCurrencyCountry_HasMinMax_Reward_Minimum_Custom() {
    let reward = Reward.template
      |> Reward.lens.minimum .~ 200

    self.vm.configureWith(data: (.template, reward: reward, 0))

    self.doneButtonIsEnabled.assertValues([true])

    self.vm.textFieldValueChanged("300")
    self.doneButtonIsEnabled.assertValues([true])

    self.vm.stepperValueChanged(100_000)
    self.doneButtonIsEnabled.assertValues([true, false])

    self.vm.textFieldValueChanged("10000")
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.stepperValueChanged(100)
    self.doneButtonIsEnabled.assertValues([true, false, true])

    self.vm.textFieldValueChanged("200")
    self.doneButtonIsEnabled.assertValues([true, false, true])
  }

  func testDoneButtonIsEnabled_Combined_ProjectCurrencyCountry_DoesNotHaveMinMax_Reward_Minimum_Template() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode

    let launchedCountries = LaunchedCountries(countries: [country])

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: .template, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(11)
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("100000")
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.stepperValueChanged(10_000)
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.textFieldValueChanged("0")
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.stepperValueChanged(10)
      self.doneButtonIsEnabled.assertValues([true, false, true])
    }
  }

  func testDoneButtonIsEnabled_Combined_ProjectCurrencyCountry_DoesNotHaveMinMax_Reward_Minimum_Custom() {
    let country = Project.Country.au
      |> Project.Country.lens.minPledge .~ nil
      |> Project.Country.lens.maxPledge .~ nil

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ country.currencyCode

    let reward = Reward.template
      |> Reward.lens.minimum .~ 200

    let launchedCountries = LaunchedCountries(countries: [country])

    withEnvironment(launchedCountries: launchedCountries) {
      self.vm.configureWith(data: (project, reward: reward, 0))

      self.doneButtonIsEnabled.assertValues([true])

      self.vm.textFieldValueChanged("300")
      self.doneButtonIsEnabled.assertValues([true])

      self.vm.stepperValueChanged(100_000)
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.stepperValueChanged(10_001)
      self.doneButtonIsEnabled.assertValues([true, false])

      self.vm.stepperValueChanged(0)
      self.doneButtonIsEnabled.assertValues([true, false, true])

      self.vm.textFieldValueChanged("200")
      self.doneButtonIsEnabled.assertValues([true, false, true])
    }
  }

  func testGenerateSelectionFeedback() {
    self.vm.configureWith(data: (.template, reward: .template, 0))
    self.generateSelectionFeedback.assertDidNotEmitValue()

    self.vm.stepperValueChanged(11)
    self.generateSelectionFeedback.assertValueCount(1)

    self.vm.stepperValueChanged(PledgeAmountStepperConstants.max)
    self.generateSelectionFeedback.assertValueCount(2)

    self.vm.stepperValueChanged(12)
    self.generateSelectionFeedback.assertValueCount(3)

    self.vm.stepperValueChanged(0)
    self.generateSelectionFeedback.assertValueCount(4)

    self.vm.stepperValueChanged(20)
    self.generateSelectionFeedback.assertValueCount(5)
  }

  // FIXME: Not sure why this notification is triggered when stepper value is inside the min/max bounds.
  func testGenerateNotificationWarningFeedback() {
    self.vm.configureWith(data: (.template, reward: .template, 0))
    self.generateNotificationWarningFeedback.assertDidNotEmitValue()

    self.vm.stepperValueChanged(11)
    self.generateNotificationWarningFeedback.assertValueCount(0)

    self.vm.stepperValueChanged(PledgeAmountStepperConstants.max)
    self.generateNotificationWarningFeedback.assertValueCount(1)

    self.vm.stepperValueChanged(12)
    self.generateNotificationWarningFeedback.assertValueCount(2)

    self.vm.stepperValueChanged(0)
    self.generateNotificationWarningFeedback.assertValueCount(3)

    self.vm.stepperValueChanged(11)
    self.generateNotificationWarningFeedback.assertValueCount(4)
  }

  func testLabelTextColor() {
    let green = LegacyColors.ksr_create_700.uiColor()
    let red = LegacyColors.ksr_alert.uiColor()

    self.vm.configureWith(data: (.template, reward: Reward.noReward, 0))

    self.labelTextColor.assertValues([green])

    self.vm.stepperValueChanged(2)
    self.labelTextColor.assertValues([green])

    self.vm.stepperValueChanged(100_000)
    self.labelTextColor.assertValues([green, red])

    self.vm.stepperValueChanged(10_000)
    self.labelTextColor.assertValues([green, red, green])

    self.vm.stepperValueChanged(0)
    self.labelTextColor.assertValues([green, red, green, red])

    self.vm.stepperValueChanged(1)
    self.labelTextColor.assertValues([green, red, green, red, green])
  }

  func testLabelTextColor_WhenShippingAmountUpdates() {
    let green = LegacyColors.ksr_create_700.uiColor()
    let red = LegacyColors.ksr_alert.uiColor()

    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.labelTextColor.assertValues([green])

    self.vm.stepperValueChanged(10_000)
    self.labelTextColor.assertValues([green])

    self.vm.unavailableAmountChanged(to: 30)
    self.labelTextColor.assertValues([green, red])

    self.vm.stepperValueChanged(9_970)
    self.labelTextColor.assertValues([green, red, green])
  }

  func testMaxPledgeAmountErrorLabelIsHidden() {
    let project = Project.template
    let reward = Reward.template
      |> Reward.lens.minimum .~ 25

    self.vm.configureWith(data: (project, reward: reward, 0))
    self.maxPledgeAmountErrorLabelIsHidden.assertValues([true])

    self.vm.stepperValueChanged(10_500)
    self.maxPledgeAmountErrorLabelIsHidden.assertValues([true, false])

    self.vm.stepperValueChanged(10_000)
    self.maxPledgeAmountErrorLabelIsHidden.assertValues([true, false, true])

    let shippingAmount = 30.0
    self.vm.unavailableAmountChanged(to: shippingAmount)
    self.maxPledgeAmountErrorLabelIsHidden.assertValues([true, false, true, false])
  }

  func testMaxPledgeAmountErrorLabelText_WithUS_CountryCurrency_Success() {
    let project = Project.template
    let reward = Reward.template
      |> Reward.lens.minimum .~ 25

    self.vm.configureWith(data: (project, reward: reward, 0))
    self.vm.stepperValueChanged(10_100)

    self.maxPledgeAmountErrorLabelText.assertValues([
      "Enter an amount less than US$ 10,000."
    ])

    self.vm.unavailableAmountChanged(to: 30.0)

    self.maxPledgeAmountErrorLabelText.assertValues([
      "Enter an amount less than US$ 10,000.",
      "Enter an amount less than US$ 9,970."
    ])
  }

  func testMaxPledgeAmountErrorLabelText_WithNonUS_CountryCurrency_Success() {
    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
    let reward = Reward.template
      |> Reward.lens.minimum .~ 25

    self.vm.configureWith(data: (project, reward: reward, 0))
    self.vm.stepperValueChanged(200_100)

    self.maxPledgeAmountErrorLabelText.assertValues([
      "Enter an amount less than MX$ 200,000."
    ])

    self.vm.unavailableAmountChanged(to: 30.0)

    self.maxPledgeAmountErrorLabelText.assertValues([
      "Enter an amount less than MX$ 200,000.",
      "Enter an amount less than MX$ 199,970."
    ])
  }

  func testStepperValueChangesWithTextFieldInput() {
    let maxValue = PledgeAmountStepperConstants.max

    self.vm.configureWith(data: (.template, reward: .template, 0))
    self.stepperValue.assertValues([0])

    self.vm.textFieldValueChanged("11")
    self.stepperValue.assertValues([0, 11])

    self.vm.textFieldValueChanged("16")
    self.stepperValue.assertValues([0, 11, 16])

    self.vm.textFieldValueChanged(String(format: "%.0f", maxValue))
    self.stepperValue.assertValues([0, 11, 16, maxValue])

    self.vm.textFieldValueChanged("0")
    self.stepperValue.assertValues([0, 11, 16, maxValue, 0])

    self.vm.textFieldValueChanged("11")
    self.stepperValue.assertValues([0, 11, 16, maxValue, 0, 11])
  }

  func testTextFieldIsFirstResponder() {
    self.vm.doneButtonTapped()

    self.textFieldIsFirstResponder.assertValue(false)
  }

  func testNilInputReturnsZero() {
    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValue(0)

    self.vm.textFieldValueChanged("11")
    self.amountIsValid.assertValues([true, true])
    self.amountMin.assertValues([0, 0])
    self.amountMax.assertValues([10_000, 10_000])
    self.amountValue.assertValues([0, 11])

    self.vm.textFieldValueChanged("")
    self.amountIsValid.assertValues([true, true, true])
    self.amountMin.assertValues([0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 11, 0])

    self.vm.textFieldValueChanged("5")
    self.amountIsValid.assertValues([true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 11, 0, 5])

    self.vm.textFieldValueChanged(nil)
    self.amountIsValid.assertValues([true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 11, 0, 5, 0])
  }

  func testTextFieldDidEndEditing() {
    let maxValue = PledgeAmountStepperConstants.max
    let maxValueFormatted = String(format: "%.0f", maxValue)

    self.vm.configureWith(data: (.template, reward: .template, 0))
    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValues([0])
    self.textFieldValue.assertValues(["0"])

    self.vm.textFieldDidEndEditing(nil)
    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValues([0])
    self.textFieldValue.assertValues(["0"])

    self.vm.textFieldDidEndEditing("16")
    self.amountIsValid.assertValues([true, true])
    self.amountMin.assertValues([0, 0])
    self.amountMax.assertValues([10_000, 10_000])
    self.amountValue.assertValues([0, 16])
    self.textFieldValue.assertValues(["0", "16"])

    self.vm.textFieldDidEndEditing(String(maxValue))
    self.amountIsValid.assertValues([true, true, false])
    self.amountMin.assertValues([0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 16, maxValue])
    self.textFieldValue.assertValues(["0", "16", maxValueFormatted])

    self.vm.textFieldDidEndEditing("0")
    self.amountIsValid.assertValues([true, true, false, true])
    self.amountMin.assertValues([0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 16, maxValue, 0])
    self.textFieldValue.assertValues(["0", "16", maxValueFormatted, "0"])

    self.vm.textFieldDidEndEditing("17")
    self.amountIsValid.assertValues([true, true, false, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 16, maxValue, 0, 17])
    self.textFieldValue.assertValues(["0", "16", maxValueFormatted, "0", "17"])

    self.vm.textFieldDidEndEditing("")
    self.amountIsValid.assertValues([true, true, false, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 16, maxValue, 0, 17])
    self.textFieldValue.assertValues(["0", "16", maxValueFormatted, "0", "17"])
  }

  func testTextFieldTextColor() {
    let green = LegacyColors.ksr_create_700.uiColor()
    let red = LegacyColors.ksr_alert.uiColor()

    self.vm.configureWith(data: (.template, reward: Reward.noReward, 0))

    self.textFieldTextColor.assertValues([green])

    self.vm.stepperValueChanged(2)
    self.textFieldTextColor.assertValues([green])

    self.vm.stepperValueChanged(100_000)
    self.textFieldTextColor.assertValues([green, red])

    self.vm.stepperValueChanged(10_000)
    self.textFieldTextColor.assertValues([green, red, green])

    self.vm.stepperValueChanged(0)
    self.textFieldTextColor.assertValues([green, red, green, red])

    self.vm.stepperValueChanged(1)
    self.textFieldTextColor.assertValues([green, red, green, red, green])
  }

  func testTextFieldValueChangedRounding() {
    let green = LegacyColors.ksr_create_700.uiColor()
    let red = LegacyColors.ksr_alert.uiColor()

    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([10_000])
    self.amountValue.assertValues([0])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10")
    self.amountIsValid.assertValues([true, true])
    self.amountMin.assertValues([0, 0])
    self.amountMax.assertValues([10_000, 10_000])
    self.amountValue.assertValues([0, 10])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10.")
    self.amountIsValid.assertValues([true, true, true])
    self.amountMin.assertValues([0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10.0")
    self.amountIsValid.assertValues([true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10, 10])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10.00")
    self.amountIsValid.assertValues([true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10, 10, 10])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10.01")
    self.amountIsValid.assertValues([true, true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10, 10, 10, 10.01])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10, 10.01])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10.010")
    self.amountIsValid.assertValues([true, true, true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10, 10, 10, 10.01, 10.01])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10, 10.01])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10.0100")
    self.amountIsValid.assertValues([true, true, true, true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10, 10, 10, 10.01, 10.01, 10.01])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10, 10.01])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10.019")
    self.amountIsValid.assertValues([true, true, true, true, true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0, 0, 0, 0, 0])
    self.amountMax.assertValues([10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10, 10, 10, 10.01, 10.01, 10.01, 10.02])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10, 10.01, 10.02])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("10.0194444444")
    self.amountIsValid.assertValues([true, true, true, true, true, true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    self.amountMax
      .assertValues([10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10, 10, 10, 10.01, 10.01, 10.01, 10.02, 10.02])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10, 10.01, 10.02])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("9.999")
    self.amountIsValid.assertValues([true, true, true, true, true, true, true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    self.amountMax
      .assertValues([10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000, 10_000])
    self.amountValue.assertValues([0, 10, 10, 10, 10, 10.01, 10.01, 10.01, 10.02, 10.02, 10])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10, 10.01, 10.02, 10])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("9.99")
    self.amountIsValid
      .assertValues([true, true, true, true, true, true, true, true, true, true, true, true])
    self.amountMin.assertValues([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    self.amountMax
      .assertValues([
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000
      ])
    self.amountValue.assertValues([0, 10, 10, 10, 10, 10.01, 10.01, 10.01, 10.02, 10.02, 10, 9.99])
    self.doneButtonIsEnabled.assertValues([true])
    self.labelTextColor.assertValues([green])
    self.stepperValue.assertValues([0, 10, 10.01, 10.02, 10, 9.99])
    self.textFieldTextColor.assertValues([green])

    self.vm.textFieldValueChanged("-1.00")
    self.amountIsValid
      .assertValues([true, true, true, true, true, true, true, true, true, true, true, true, false])
    self.amountMin.assertValues([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    self.amountMax
      .assertValues([
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000,
        10_000
      ])
    self.amountValue.assertValues([0, 10, 10, 10, 10, 10.01, 10.01, 10.01, 10.02, 10.02, 10, 9.99, -1.0])
    self.doneButtonIsEnabled.assertValues([true, false])
    self.labelTextColor.assertValues([green, red])
    self.stepperValue.assertValues([0, 10, 10.01, 10.02, 10, 9.99, -1.0])
    self.textFieldTextColor.assertValues([green, red])
  }

  func testTextFieldDidEndEditingRoundingAndTruncation() {
    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.textFieldValue.assertValues(["0"])

    self.vm.textFieldDidEndEditing("10.")
    self.textFieldValue.assertValues(["0", "10"])

    self.vm.textFieldDidEndEditing("10.0")
    self.textFieldValue.assertValues(["0", "10", "10"])

    self.vm.textFieldDidEndEditing("10.00")
    self.textFieldValue.assertValues(["0", "10", "10", "10"])

    self.vm.textFieldDidEndEditing("10.01")
    self.textFieldValue.assertValues(["0", "10", "10", "10", "10.01"])

    self.vm.textFieldDidEndEditing("10.010")
    self.textFieldValue.assertValues(["0", "10", "10", "10", "10.01", "10.01"])

    self.vm.textFieldDidEndEditing("10.0100")
    self.textFieldValue.assertValues(["0", "10", "10", "10", "10.01", "10.01", "10.01"])

    self.vm.textFieldDidEndEditing("10.019")
    self.textFieldValue.assertValues(["0", "10", "10", "10", "10.01", "10.01", "10.01", "10.02"])

    self.vm.textFieldDidEndEditing("10.0194444444")
    self.textFieldValue.assertValues(["0", "10", "10", "10", "10.01", "10.01", "10.01", "10.02", "10.02"])

    self.vm.textFieldDidEndEditing("9.999")
    self.textFieldValue
      .assertValues(["0", "10", "10", "10", "10.01", "10.01", "10.01", "10.02", "10.02", "10"])

    self.vm.textFieldDidEndEditing("9.99")
    self.textFieldValue
      .assertValues(["0", "10", "10", "10", "10.01", "10.01", "10.01", "10.02", "10.02", "10", "9.99"])
  }

  func testPlusSignLabelHidden_NoReward() {
    self.plusSignLabelHidden.assertDidNotEmitValue()

    self.vm.configureWith(data: (.template, reward: .noReward, 0))

    self.plusSignLabelHidden.assertValues([true])
  }

  func testPlusSignLabelHidden_RegularReward() {
    self.plusSignLabelHidden.assertDidNotEmitValue()

    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.plusSignLabelHidden.assertValues([false])
  }

  func testSubtitleLabelHidden_NoReward() {
    self.subTitleLabelHidden.assertDidNotEmitValue()

    self.vm.configureWith(data: (.template, reward: .noReward, 0))

    self.subTitleLabelHidden.assertValues([true])
  }

  func testSubtitleLabelHidden_RegularReward() {
    self.plusSignLabelHidden.assertDidNotEmitValue()

    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.plusSignLabelHidden.assertValues([false])
  }

  func testTitleLabelText_NoReward() {
    self.titleLabelText.assertDidNotEmitValue()

    self.vm.configureWith(data: (.template, reward: .noReward, 0))

    self.titleLabelText.assertValues(["Your pledge amount"])
  }

  func testTitleLabelText_RegularReward() {
    self.titleLabelText.assertDidNotEmitValue()

    self.vm.configureWith(data: (.template, reward: .template, 0))

    self.titleLabelText.assertValues(["Bonus support"])
  }

  func testCurrentAmount_BackedReward_EditingSameReward() {
    let reward = Reward.template

    let project = Project.cosmicSurgery
      |> Project.lens.state .~ .live
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ reward
          |> Backing.lens.rewardId .~ reward.id
          |> Backing.lens.shippingAmount .~ 10
          |> Backing.lens.amount .~ 700.0
          |> Backing.lens.status .~ .pledged
      )

    self.amountIsValid.assertDidNotEmitValue()
    self.amountMin.assertDidNotEmitValue()
    self.amountMax.assertDidNotEmitValue()
    self.amountValue.assertDidNotEmitValue()
    self.currency.assertDidNotEmitValue()
    self.stepperMinValue.assertDidNotEmitValue()
    self.stepperMaxValue.assertDidNotEmitValue()
    self.stepperValue.assertDidNotEmitValue()
    self.textFieldValue.assertDidNotEmitValue()

    self.vm.configureWith(data: (project, reward: reward, 50))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([8_000])
    self.amountValue.assertValues([50])
    self.currency.assertValues(["£"])
    self.stepperMinValue.assertValue(0)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([50.0])
    self.textFieldValue.assertValues(["50"])
  }

  func testCurrentAmount_BackedReward_EditingDifferentReward() {
    let reward = Reward.template
    let otherReward = Reward.template
      |> Reward.lens.id .~ 5

    let project = Project.cosmicSurgery
      |> Project.lens.state .~ .live
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ reward
          |> Backing.lens.rewardId .~ reward.id
          |> Backing.lens.shippingAmount .~ 10
          |> Backing.lens.amount .~ 700.0
          |> Backing.lens.status .~ .pledged
      )

    self.amountIsValid.assertDidNotEmitValue()
    self.amountMin.assertDidNotEmitValue()
    self.amountMax.assertDidNotEmitValue()
    self.amountValue.assertDidNotEmitValue()
    self.currency.assertDidNotEmitValue()
    self.stepperMinValue.assertDidNotEmitValue()
    self.stepperMaxValue.assertDidNotEmitValue()
    self.stepperValue.assertDidNotEmitValue()
    self.textFieldValue.assertDidNotEmitValue()

    self.vm.configureWith(data: (project, reward: otherReward, 50))

    self.amountIsValid.assertValues([true])
    self.amountMin.assertValues([0])
    self.amountMax.assertValues([8_000])
    self.amountValue.assertValues([50])
    self.currency.assertValues(["£"])
    self.stepperMinValue.assertValue(0)
    self.stepperMaxValue.assertValue(PledgeAmountStepperConstants.max)
    self.stepperValue.assertValues([50.0])
    self.textFieldValue.assertValues(["50"])
  }
}

private final class AmountRecording<Value> {
  private(set) var values: [Value] = []
  func append(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension AmountRecording where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, [expected], message, file: file, line: line)
  }
}
