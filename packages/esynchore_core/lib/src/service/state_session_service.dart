import "package:esynchore_core/src/models/state_command.dart";
import "package:esynchore_core/src/service/state_handler.dart";

/// Owns the state handlers for a set of uniquely identified sessions.
///
/// Share one service instance between the HTTP and WebSocket routes in a
/// server process. This in-memory service does not coordinate across isolates
/// or server processes; deployments must route a session to its owning process.
class StateSessionService<State, Credentials, Principal> {
  /// Creates a service whose sessions use [authenticate].
  StateSessionService({required this.authenticate});

  /// Authenticates credentials against the current session state.
  final Authenticator<State, Credentials, Principal> authenticate;

  final Map<String, StateHandler<State, Credentials, Principal>> _sessions = {};
  final Map<String, Future<bool>> _removing = {};
  Future<void>? _closing;

  /// Creates the unique handler for [id] with [initialState].
  ///
  /// Throws [StateError] if the ID is already in use or the service is closing.
  StateHandler<State, Credentials, Principal> create(
    String id,
    State initialState, {
    void Function(
      StateCommand<State, Principal> command,
      Principal principal,
      State state,
    )?
    onApplied,
    void Function(Object error, StackTrace stackTrace)? onObserverError,
  }) {
    if (_closing != null) throw StateError("The session service is closing.");
    if (_sessions.containsKey(id))
      throw StateError("The session already exists: $id");
    final handler = StateHandler<State, Credentials, Principal>(
      initialState: initialState,
      authenticate: authenticate,
      onApplied: onApplied,
      onObserverError: onObserverError,
    );
    _sessions[id] = handler;
    return handler;
  }

  /// Returns the active handler for [id], or null if it does not exist.
  ///
  /// A session being removed is no longer available for new requests.
  StateHandler<State, Credentials, Principal>? get(String id) =>
      _closing != null || _removing.containsKey(id) ? null : _sessions[id];

  /// Drains and removes the handler for [id].
  ///
  /// Returns false if the ID does not exist. The ID remains reserved until
  /// draining finishes, including when multiple callers remove it concurrently.
  Future<bool> remove(String id) {
    final pending = _removing[id];
    if (pending != null) return pending;
    final handler = _sessions[id];
    if (handler == null) return Future.value(false);
    final removal = _remove(id, handler);
    _removing[id] = removal;
    return removal;
  }

  Future<bool> _remove(
    String id,
    StateHandler<State, Credentials, Principal> handler,
  ) async {
    try {
      await handler.close();
      return true;
    } finally {
      _sessions.remove(id);
      _removing.remove(id)?.ignore();
    }
  }

  /// Stops accepting sessions and drains all owned handlers.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await Future.wait(_sessions.keys.toList().map(remove));
  }
}
