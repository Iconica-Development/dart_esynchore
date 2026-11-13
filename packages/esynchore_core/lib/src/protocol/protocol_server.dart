import "dart:async";
import "dart:convert";

import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_core/src/models/esynchore_error.dart";
import "package:esynchore_core/src/protocol/protocol_message.dart";
import "package:esynchore_core/src/service/state_handler.dart";
import "package:fpdart/fpdart.dart";
import "package:synchronized/synchronized.dart";

/// A server-side protocol session for a single transport connection.
///
/// Subscribe to [outgoing] before passing incoming text frames to [receive].
/// The transport must close this session when the connection ends. The session
/// does not close the shared [handler], which can serve multiple connections.
///
/// Only authenticated clients receive state. [projectState] must select only
/// information the principal is allowed to see, and [stateSerializer] must
/// encode that projected view. Commands are handled separately from this
/// WebSocket protocol.
class ProtocolServerSession<ChoreState, Credentials, Principal, View> {
  /// Creates a protocol session using application-provided serializers.
  ProtocolServerSession({
    required this.handler,
    required this.credentialsSerializer,
    required this.stateSerializer,
    required this.projectState,
    this.projectPublicState,
    this.onAuthenticated,
    this.onClosed,
    this.messageSerializer,
    this.sendStateOnPing = false,
    this.onUnexpectedError,
  });

  /// The shared state and command coordinator.
  final StateHandler<ChoreState, Credentials, Principal> handler;

  /// Decodes credentials received from clients.
  final Serializer<Credentials> credentialsSerializer;

  /// Encodes the projected state sent to this connection.
  final Serializer<View> stateSerializer;

  /// Produces a view of [ChoreState] appropriate for the authenticated principal.
  final View Function(ChoreState state, Principal principal) projectState;

  /// Selects the public view, or null to withhold state until authentication.
  final View Function(ChoreState state)? projectPublicState;

  /// Runs after authentication and before the acknowledgement and state view.
  final FutureOr<void> Function(Credentials credentials, Principal principal)? onAuthenticated;

  /// Runs once when the connection closes, with its authenticated principal.
  final FutureOr<void> Function(Principal? principal)? onClosed;

  /// Overrides the default versioned protocol's message representation.
  final Serializer<ProtocolMessage>? messageSerializer;

  /// Sends the current visible state after each heartbeat response.
  final bool sendStateOnPing;

  /// Receives unexpected failures for server-side logging.
  final void Function(Object error, StackTrace stackTrace)? onUnexpectedError;

  final StreamController<String> _outgoing = StreamController<String>.broadcast();
  StateSession<ChoreState, Credentials, Principal>? _session;
  StreamSubscription<ChoreState>? _stateSubscription;
  final _lock = Lock();
  Future<void>? _closing;
  Principal? _lifecyclePrincipal;
  bool _started = false;
  bool _authenticating = false;
  bool _stateChangedDuringAuthentication = false;

  /// JSON text frames to send to this connection.
  Stream<String> get outgoing => _outgoing.stream;

  /// Starts public state updates and announces authentication when configured.
  ///
  /// Subscribe to [outgoing] first. Calling this more than once has no effect.
  void start() {
    if (_closing != null) throw StateError("The protocol session is closed.");
    if (_started) return;
    _started = true;
    if (projectPublicState != null) {
      _subscribeToState();
      _sendState(handler.state);
      _send(const AuthenticationRequiredMessage());
    }
  }

  /// Publishes the latest state visible to this connection, if any.
  void sendCurrentState() => _sendState(handler.state);

  void _subscribeToState() {
    _stateSubscription ??= handler.stateChanges.listen((state) {
      if (_authenticating) {
        _stateChangedDuringAuthentication = true;
      } else {
        _sendState(state);
      }
    }, onError: _reportUnexpected);
  }

  /// Processes a JSON text frame after earlier frames from this connection.
  ///
  /// Invalid requests receive protocol errors. Unexpected application errors
  /// are reported to [onUnexpectedError] and produce a generic protocol error.
  /// Throws [StateError] after closing starts.
  Future<void> receive(String frame) {
    if (_closing != null) throw StateError("The protocol session is closed.");
    return _lock.synchronized(() async {
      await _receive(frame).run();
    });
  }

  Task<Unit> _receive(String frame) => .Do(($) async {
    ProtocolMessage? message;
    try {
      final decoded = _decodeMessage(frame);
      message = decoded.match(
        (_) {
          _error(
            null,
            EsynchoreErrorCodes.invalidMessage,
            "Invalid protocol message.",
          );
          return null;
        },
        (message) => message,
      );
      if (message == null) return unit;
      await $(_handleMessage(message));
    } on FormatException {
      _error(
        _requestId(message),
        EsynchoreErrorCodes.invalidPayload,
        "Invalid request payload.",
      );
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace);
      _error(
        _requestId(message, includePing: true),
        EsynchoreErrorCodes.internalError,
        "The request could not be processed.",
      );
    }
    return unit;
  });

  Either<FormatException, ProtocolMessage> _decodeMessage(String frame) => Either.tryCatch(
    () {
      final decoded = jsonDecode(frame);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException("Expected a protocol object.");
      }
      return (messageSerializer ?? protocolMessageSerializer).fromMap(
        decoded,
      );
    },
    (error, stackTrace) {
      if (error is FormatException) return error;
      Error.throwWithStackTrace(error, stackTrace);
    },
  );

  Task<Unit> _handleMessage(ProtocolMessage message) => .Do(($) async {
    switch (message) {
      case AuthenticateMessage():
        await $(_authenticate(message));
      case PingMessage():
        _send(PongMessage(message.requestId));
        if (sendStateOnPing) _sendState(handler.state);
      case _:
        _error(
          null,
          EsynchoreErrorCodes.unexpectedMessage,
          "This message cannot be sent to the server.",
        );
    }
    return unit;
  });

  Task<Unit> _authenticate(AuthenticateMessage message) => .Do(($) async {
    if (_session != null) {
      _error(
        message.requestId,
        EsynchoreErrorCodes.alreadyAuthenticated,
        "The connection is already authenticated.",
      );
      return unit;
    }

    final credentials = credentialsSerializer.fromMap(message.credentials);
    _authenticating = true;
    _stateChangedDuringAuthentication = false;
    try {
      final result = await handler.openSession(credentials).run();
      await result.match(
        (error) async {
          _sendFailure(message.requestId, error);
          if (_stateChangedDuringAuthentication) _sendState(handler.state);
        },
        (session) async {
          _lifecyclePrincipal = session.principal;
          await onAuthenticated?.call(credentials, session.principal);
          _session = session;
          _subscribeToState();
          _send(AuthenticatedMessage(message.requestId));
          _sendState(handler.state);
        },
      );
    } finally {
      _authenticating = false;
    }
    return unit;
  });

  String? _requestId(ProtocolMessage? message, {bool includePing = false}) => switch (message) {
    AuthenticateMessage(:final requestId) => requestId,
    PingMessage(:final requestId) when includePing => requestId,
    _ => null,
  };

  void _sendState(ChoreState state) {
    try {
      final session = _session;
      final View view;
      if (session == null) {
        final project = projectPublicState;
        if (project == null) return;
        view = project(state);
      } else {
        view = projectState(state, session.principal);
      }
      _send(
        StateMessage(Map<String, dynamic>.from(stateSerializer.toMap(view))),
      );
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace);
      _error(null, EsynchoreErrorCodes.stateEncodingFailed, "The state could not be sent.");
    }
  }

  void _sendFailure(String requestId, EsynchoreError error) {
    final category = switch (error) {
      AuthenticationError() => ProtocolErrorCategory.authentication,
      AuthorizationError() => ProtocolErrorCategory.authorization,
      ApplicationError() => ProtocolErrorCategory.application,
    };
    _send(
      ErrorMessage(
        requestId: requestId,
        category: category,
        code: error.code,
        message: error.message,
      ),
    );
  }

  void _error(String? requestId, String code, String message) => _send(
    ErrorMessage(
      requestId: requestId,
      category: ProtocolErrorCategory.protocol,
      code: code,
      message: message,
    ),
  );

  void _send(ProtocolMessage message) => _outgoing.add(
    jsonEncode((messageSerializer ?? protocolMessageSerializer).toMap(message)),
  );

  void _reportUnexpected(Object error, StackTrace stackTrace) => onUnexpectedError?.call(error, stackTrace);

  /// Stops accepting frames, finishes queued requests, and closes [outgoing].
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _lock.synchronized(() {});
      await _stateSubscription?.cancel();
      await onClosed?.call(_lifecyclePrincipal);
    } finally {
      await _outgoing.close();
    }
  }
}
