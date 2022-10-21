import Combine
import ComposableArchitecture
import XCTest

@MainActor
final class PresentationTests: XCTestCase {
  func testCancelEffectsOnDismissal() async {
    let store = TestStore(
      initialState: Feature.State(),
      reducer: Feature()
    )

    await store.send(.button1Tapped) {
      $0.child1 = Child.State()
    }
    await store.send(.child1(.presented(.onAppear)))
    await store.send(.child1(.dismiss)) {
      $0.child1 = nil
    }
  }

  func testChildDismissing() async {
    let store = TestStore(
      initialState: Feature.State(),
      reducer: Feature()
    )

    await store.send(.button1Tapped) {
      $0.child1 = Child.State()
    }
    await store.send(.child1(.presented(.closeButtonTapped)))
    await store.receive(.child1(.dismiss)) {
      $0.child1 = nil
    }
  }

  func testPresentWithNil() async {
    let store = TestStore(
      initialState: Feature.State(),
      reducer: Feature()
    )

    await store.send(.child1(.present(id: UUID(), nil))) {
      $0.child1 = Child.State()
    }
    await store.send(.child1(.dismiss)) {
      $0.child1 = nil
    }
  }

  func testPresentWithState() async {
    let store = TestStore(
      initialState: Feature.State(),
      reducer: Feature()
    )

    await store.send(.child1(.present(id: UUID(), Child.State(count: 42)))) {
      $0.child1 = Child.State(count: 42)
    }
    await store.send(.child1(.dismiss)) {
      $0.child1 = nil
    }
  }

  func testChildEffect() async {
    let store = TestStore(
      initialState: Feature.State(),
      reducer: Feature()
    )

    store.dependencies.mainQueue = .immediate

    await store.send(.child1(.present(id: UUID(), nil))) {
      $0.child1 = Child.State()
    }
    await store.send(.child1(.presented(.performButtonTapped)))
    await store.receive(.child1(.presented(.response(1)))) {
      $0.child1?.count = 1
    }
    await store.send(.child1(.dismiss)) {
      $0.child1 = nil
    }
  }

  func testMultiplePresentations() async {
    let store = TestStore(
      initialState: Feature.State(),
      reducer: Feature()
    )

    await store.send(.button1Tapped) {
      $0.child1 = Child.State()
    }
    await store.send(.button2Tapped) {
      $0.child2 = Child.State()
    }
    await store.send(.child1(.presented(.closeButtonTapped)))
    await store.receive(.child1(.dismiss)) {
      $0.child1 = nil
    }
    await store.send(.child2(.presented(.closeButtonTapped)))
    await store.receive(.child2(.dismiss)) {
      $0.child2 = nil
    }
  }

  func testWarnWhenSendingActionToNilChildState() async {
    struct Feature: ReducerProtocol {
      struct State: Equatable {
        @PresentationState<Int> var child
      }
      enum Action {
        case child(PresentationAction<Int, Void>)
      }
      var body: some ReducerProtocol<State, Action> {
        EmptyReducer()
          .presentationDestination(\.$child, action: /Action.child) {}
      }
    }
    let line = #line - 3

    let store = TestStore(
      initialState: Feature.State(),
      reducer: Feature()
    )

    XCTExpectFailure {
      $0.compactDescription == """
        A "presentationDestination" at "ComposableArchitectureTests/PresentationTests.swift:\
        \(line)" received a destination action when destination state was absent. …

          Action:
            PresentationTests.Feature.Action.child(.presented)

        This is generally considered an application logic error, and can happen for a few reasons:

        • A parent reducer set destination state to "nil" before this reducer ran. This reducer \
        must run before any other reducer sets destination state to "nil". This ensures that \
        destination reducers can handle their actions while their state is still present.

        • This action was sent to the store while destination state was "nil". Make sure that \
        actions for this reducer can only be sent from a view store when state is present, or from \
        effects that start from this reducer. In SwiftUI applications, use a Composable \
        Architecture view modifier like "sheet(store:…)".
        """
    }

    await store.send(.child(.presented(())))
  }

  func testResetStateCancelsEffects() async {
    let mainQueue = DispatchQueue.test
    let store = TestStore(
      initialState: Feature.State(),
      reducer: Feature()
    )
    store.dependencies.mainQueue = mainQueue.eraseToAnyScheduler()
    store.dependencies.uuid = .incrementing

    await store.send(.button1Tapped) {
      $0.child1 = Child.State()
    }
    await store.send(.child1(.presented(.performButtonTapped)))
    await store.send(.reset1ButtonTapped)
    await mainQueue.run()
    await store.send(.child1(.dismiss)) {
      $0.child1 = nil
    }
  }
}

private struct Feature: ReducerProtocol {
  struct State: Equatable {
    @PresentationStateOf<Child> var child1
    @PresentationStateOf<Child> var child2
  }
  enum Action: Equatable {
    case button1Tapped
    case button2Tapped
    case child1(PresentationActionOf<Child>)
    case child2(PresentationActionOf<Child>)
    case reset1ButtonTapped
  }
  @Dependency(\.uuid) var uuid
  var body: some ReducerProtocol<State, Action> {
    Reduce { state, action in
      switch action {
      case .button1Tapped:
        state.child1 = Child.State()
        return .none
      case .button2Tapped:
        state.child2 = Child.State()
        return .none
      case let .child1(.present(id: _, childState)):
        state.child1 = childState ?? Child.State()
        return .none
      case .child1:
        return .none
      case let .child2(.present(id: _, childState)):
        state.child2 = childState ?? Child.State()
        return .none
      case .child2:
        return .none
      case .reset1ButtonTapped:
        state.$child1 = .presented(id: self.uuid(), Child.State())
        return .none
      }
    }
    .presentationDestination(\.$child1, action: /Action.child1) {
      Child()
    }
    .presentationDestination(\.$child2, action: /Action.child2) {
      Child()
    }
  }
}

private struct Child: ReducerProtocol {
  struct State: Equatable {
    var count = 0
  }
  enum Action: Equatable {
    case closeButtonTapped
    case onAppear
    case performButtonTapped
    case response(Int)
  }
  @Dependency(\.dismiss) var dismiss
  @Dependency(\.mainQueue) var mainQueue
  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .closeButtonTapped:
      return .fireAndForget {
        await self.dismiss()
      }

    case .onAppear:
      return .run { _ in try await Task.never() }

    case .performButtonTapped:
      return .run { [count = state.count] send in
        try await self.mainQueue.sleep(for: .seconds(1))
        await send(.response(count + 1))
      }

    case let .response(value):
      state.count = value
      return .none
    }
  }
}
