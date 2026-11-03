import Foundation
import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol MessagesSearchViewModelInputs {
  /// Call when the search clear button is tapped.
  func clearSearchText()

  /// Call with the (optional) project given to the view.
  func configureWith(project: Project?)

  /// Call when the search text changes.
  func searchTextChanged(_ searchText: String?)

  /// Call when a message thread is tapped.
  func tappedMessageThread(_ messageThread: MessageThread)

  /// Call when the view loads.
  func viewDidLoad()

  /// Call when the view will appear.
  func viewWillAppear()

  /// Call when the view will disappear.
  func viewWillDisappear()
}

@MainActor
public protocol MessagesSearchViewModelOutputs {
  /// Emits a boolean that determines if the empty state is visible.
  var emptyStateIsVisible: Signal<Bool, Never> { get }

  /// Emits when we should navigate to the message thread.
  var goToMessageThread: Signal<MessageThread, Never> { get }

  /// Emits a boolean that determines if a search request is currently in-flight.
  var isSearching: Signal<Bool, Never> { get }

  /// Emits an array of message threads to be displayed.
  var messageThreads: Signal<[MessageThread], Never> { get }

  /// Emits a boolean that determines if the keyboard should be shown or not.
  var showKeyboard: Signal<Bool, Never> { get }
}

@MainActor
public protocol MessagesSearchViewModelType {
  var inputs: MessagesSearchViewModelInputs { get }
  var outputs: MessagesSearchViewModelOutputs { get }
}

@MainActor
public final class MessagesSearchViewModel: MessagesSearchViewModelType, MessagesSearchViewModelInputs,
  MessagesSearchViewModelOutputs {
  private let feature: MessagingFeature
  public convenience init() { self.init(feature: AppModel.shared.messagingFeature) }
  public init(feature: MessagingFeature) {
    self.feature = feature
    let isLoading = MutableProperty(false)

    let project = self.projectProperty.producer
      .takeWhen(self.viewDidLoadProperty.signal)

    let query = Signal
      .merge(
        self.searchTextChangedProperty.signal,
        self.clearSearchTextProperty.signal.mapConst("")
      )
      .skipRepeats()

    let route = self.route
    var isVisible = true
    self.viewWillAppearProperty.signal.observeValues { isVisible = true }
    self.viewWillDisappearProperty.signal.observeValues { isVisible = false }
    var queryRevision = 0
    query.observeValues { _ in
      queryRevision += 1
      feature.cancelRead(route: route)
    }
    let clears = query.map(const([MessageThread]()))

    let searchResults = query
      .ksr_debounce(AppEnvironment.current.debounceInterval, on: AppEnvironment.current.scheduler)
      .skipRepeats()
      .filter { !$0.isEmpty && isVisible }
      .combineLatest(with: project)
      .switchMap { query, project in
        let revision = queryRevision
        return feature.readResult(route: route) { try await feature.search(query: query, project: project) }
          .on(
            starting: { isLoading.value = true },
            terminated: { if revision == queryRevision { isLoading.value = false } }
          )
          .materialize()
      }

    self.messageThreads = Signal.merge(clears, searchResults.values())
      .skip(while: { $0.isEmpty })
      .skipRepeats(==)

    self.showKeyboard = Signal.merge(
      self.viewWillAppearProperty.signal.mapConst(true),
      self.viewWillDisappearProperty.signal.mapConst(false)
    )

    self.emptyStateIsVisible = .empty

    self.isSearching = Signal.merge(
      self.viewDidLoadProperty.signal.take(first: 1).mapConst(false),
      query.map { !$0.isEmpty },
      isLoading.signal
    ).skipRepeats()

    self.goToMessageThread = self.tappedMessageThreadProperty.signal.skipNil()
  }

  private let route = UUID()
  deinit {
    let feature = self.feature, route = self.route
    Task { @MainActor in feature.release(route: route) }
  }

  fileprivate let clearSearchTextProperty = MutableProperty(())
  public func clearSearchText() {
    self.clearSearchTextProperty.value = ()
  }

  fileprivate let projectProperty = MutableProperty<Project?>(nil)
  public func configureWith(project: Project?) {
    self.projectProperty.value = project
  }

  fileprivate let searchTextChangedProperty = MutableProperty<String>("")
  public func searchTextChanged(_ searchText: String?) {
    self.searchTextChangedProperty.value = searchText ?? ""
  }

  fileprivate let tappedMessageThreadProperty = MutableProperty<MessageThread?>(nil)
  public func tappedMessageThread(_ messageThread: MessageThread) {
    self.tappedMessageThreadProperty.value = messageThread
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  fileprivate let viewWillAppearProperty = MutableProperty(())
  public func viewWillAppear() {
    self.viewWillAppearProperty.value = ()
  }

  fileprivate let viewWillDisappearProperty = MutableProperty(())
  public func viewWillDisappear() {
    self.feature.cancelRead(route: self.route)
    self.viewWillDisappearProperty.value = ()
  }

  public let emptyStateIsVisible: Signal<Bool, Never>
  public let goToMessageThread: Signal<MessageThread, Never>
  public let isSearching: Signal<Bool, Never>
  public let messageThreads: Signal<[MessageThread], Never>
  public let showKeyboard: Signal<Bool, Never>

  public var inputs: MessagesSearchViewModelInputs { return self }
  public var outputs: MessagesSearchViewModelOutputs { return self }
}
