import "dart:async";

import "package:esynchore_core/src/models/esynchore_error.dart";
import "package:esynchore_core/src/models/state_command.dart";
import "package:fpdart/fpdart.dart";
import "package:synchronized/synchronized.dart";

/// Resolves credentials to a principal or an authentication failure.
///
/// [state] is the current state when authentication starts. Authorization is
/// checked separately against the current state when a command is processed.
typedef Authenticator<State, Credentials, Principal> = TaskEither<AuthenticationError, Principal> Function(
  State state,
  Credentials credentials,
);

/// Coordinates authenticated commands against one shared state.
///
/// Submissions are processed in the order they are received. A successful
/// command replaces the current state and publishes it to [stateChanges]. An
/// authorization or application failure leaves the state unchanged.
///
/// State objects must be immutable: the handler cannot enforce deep
/// immutability or protect against mutations performed by application code.
class StateHandler<StateType, Credentials, Principal> {
  /// Creates a handler with an initial state and an authentication policy.
  StateHandler({
    required StateType initialState,
    required this.authenticate,
    this.onApplied,
    this.onObserverError,
  }) : _state = initialState;

  /// Resolves credentials when opening a session.
  final Authenticator<StateType, Credentials, Principal> authenticate;

  /// Runs synchronously after a successful state replacement, before publication.
  ///
  /// This hook may schedule persistence or other observation, but should not
  /// mutate the state. Failures do not undo or reject an applied command.
  final void Function(
    StateCommand<StateType, Principal> command,
    Principal principal,
    StateType state,
  )?
  onApplied;

  /// Receives unexpected failures from [onApplied].
  ///
  /// Without a callback, failures are reported to the current zone.
  final void Function(Object error, StackTrace stackTrace)? onObserverError;

  StateType _state;
  final StreamController<StateType> _changes = StreamController<StateType>.broadcast();
  Future<void>? _closing;

  /// Serializes state changes and is held while a queued command is applied.
  final lock = Lock();

  /// The latest successfully applied state.
  StateType get state => _state;

  /// Successfully applied states, excluding the initial state.
  ///
  /// This broadcast stream does not replay previous updates. Read [state] for
  /// the current value.
  Stream<StateType> get stateChanges => _changes.stream;

  /// Authenticates [credentials] and opens a session bound to the principal.
  ///
  /// Authentication failure is returned as a [Left]. Throws [StateError] if
  /// the handler has started closing, including while authentication awaits.
  TaskEither<AuthenticationError, StateSession<StateType, Credentials, Principal>> openSession(
    Credentials credentials,
  ) => .Do(($) async {
    await $(.fromEither(_checkOpen()));
    final principal = await $(authenticate(_state, credentials));
    await $(.fromEither(_checkOpen()));
    return StateSession._(this, principal);
  });

  TaskEither<EsynchoreError, StateType> _submit(
    StateCommand<StateType, Principal> command,
    Principal principal,
  ) => .Do(
    ($) async => $(_enqueue(() => _apply(command, principal))),
  );

  /// Authenticates [credentials] and applies [command] in submission order.
  ///
  /// Authentication and authorization use the current state when this request
  /// reaches the queue. Closing the handler drains requests accepted here,
  /// including any whose authentication has not finished yet.
  TaskEither<EsynchoreError, StateType> submit(
    StateCommand<StateType, Principal> command,
    Credentials credentials,
  ) => _enqueue(
    () => authenticate(
      _state,
      credentials,
    ).mapLeft<EsynchoreError>((e) => e).flatMap((principal) => _apply(command, principal)),
  );

  TaskEither<EsynchoreError, StateType> _enqueue(
    TaskEither<EsynchoreError, StateType> Function() operation,
  ) => .Do(($) async {
    await $(.fromEither(_checkOpen()));
    final result = await lock.synchronized(() => operation().run());
    return $(.fromEither(result));
  });

  TaskEither<EsynchoreError, StateType> _apply(
    StateCommand<StateType, Principal> command,
    Principal principal,
  ) => .Do(($) async {
    await $(command.authorize(_state, principal));

    final newState = await $(command.apply(state, principal));

    _state = newState;

    runCaptured(() => onApplied?.call(command, principal, newState));
    _changes.add(newState);

    return newState;
  });

  /// Stops accepting sessions and submissions, then drains queued commands.
  ///
  /// The state-change stream closes after the queue has drained. Repeated calls
  /// return the same future.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    // Request the lock, anything happening after this
    await lock.synchronized(() => Future.delayed(Duration.zero));
    await _changes.close();
  }

  Either<AuthenticationError, Unit> _checkOpen() => .fromPredicate(
    unit,
    (_) => _closing == null,
    (_) => const AuthenticationError(
      EsynchoreErrorCodes.actionOnClosedConnection,
      "A modification attempt was made whilst closing a connection",
    ),
  );

  /// Runs [toCapture] and reports observer failures without rejecting a command.
  void runCaptured(void Function() toCapture) {
    final report = onObserverError ?? Zone.current.handleUncaughtError;
    try {
      toCapture();
    } on Object catch (error, stackTrace) {
      try {
        report(error, stackTrace);
      } on Object catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
  }
}

/// A session bound to a principal authenticated by a [StateHandler].
///
/// The session does not automatically expire or reauthenticate. Applications
/// should check revocation and changing permissions in command authorization.
class StateSession<StateType, Credentials, Principal> {
  StateSession._(this._handler, this.principal);

  final StateHandler<StateType, Credentials, Principal> _handler;

  /// The principal established when this session was opened.
  final Principal principal;

  /// Submits [command] for authorization and ordered application.
  ///
  /// Expected failures are returned as [AuthorizationError] or
  /// [ApplicationError]. Unexpected exceptions complete the future with that
  /// exception and do not prevent subsequent queued commands from running.
  /// Throws [StateError] if the handler has started closing.
  TaskEither<EsynchoreError, StateType> submit(
    StateCommand<StateType, Principal> command,
  ) => _handler._submit(command, principal);
}
