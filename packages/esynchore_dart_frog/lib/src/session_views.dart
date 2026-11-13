import "dart:async";

import "package:dart_frog/dart_frog.dart";
import "package:dart_frog_utils/dart_frog_utils.dart";
import "package:esynchore_backend/esynchore_backend.dart";
import "package:esynchore_core/esynchore_core.dart";

/// Provides an existing session service to Dart Frog request contexts.
///
/// Construct [sessions] once for the server process, not once per request.
/// The application owns the service and must close it during shutdown.
Middleware stateSessionProvider<State, Credentials, Principal>(
  StateSessionService<State, Credentials, Principal> sessions,
) => provider<StateSessionService<State, Credentials, Principal>>(
  (_) => sessions,
);

/// Creates a Dart Frog WebSocket handler with connection-local configuration.
///
/// [createSession] receives the handler owned by [sessions]. It may create
/// connection-specific projections, serializers, and lifecycle callbacks.
Handler sessionWebSocketViewFromFactory<State, Credentials, Principal, View>({
  required StateSessionService<State, Credentials, Principal> sessions,
  required String id,
  required ProtocolServerSession<State, Credentials, Principal, View> Function(
    StateHandler<State, Credentials, Principal> handler,
  )
  createSession,
  void Function()? onConnectionOpened,
  void Function(
    ProtocolServerSession<State, Credentials, Principal, View> session,
  )?
  onStarted,
  Iterable<String>? allowedOrigins,
  Duration? pingInterval,
  void Function(Object error, StackTrace stackTrace)? onUnexpectedError,
}) => fromShelfHandler(
  sessionWebSocketHandlerFromFactory(
    sessions: sessions,
    id: id,
    createSession: createSession,
    onConnectionOpened: onConnectionOpened,
    onStarted: onStarted,
    allowedOrigins: allowedOrigins,
    pingInterval: pingInterval,
    onUnexpectedError: onUnexpectedError,
  ),
);

abstract class _SessionView extends BaseView {
  @override
  Future<Response> asView(RequestContext context) async {
    try {
      return await super.asView(context);
    } on MethodNotAllowedException catch (error) {
      return methodNotAllowedHandler(context, error);
    }
  }
}

/// Handles POST commands for a single shared state session.
///
/// Create this view with the route's session ID and invoke [asView], or use
/// `context.view(view)`. Credentials are read independently for each request.
class SessionCommandView<State, Credentials, Principal> extends _SessionView with PostMixin {
  /// Creates a command view backed by [sessions].
  SessionCommandView({
    required this.sessions,
    required this.id,
    required this.commandSerializer,
    required this.readCredentials,
    this.onUnexpectedError,
  });

  /// The shared service that owns the session.
  final StateSessionService<State, Credentials, Principal> sessions;

  /// The session ID obtained from the route.
  final String id;

  /// Decodes the application's JSON command payload.
  final Serializer<StateCommand<State, Principal>> commandSerializer;

  /// Reads credentials from the incoming HTTP request.
  final FutureOr<Credentials> Function(RequestContext context) readCredentials;

  /// Receives unexpected failures for server-side logging.
  final void Function(Object error, StackTrace stackTrace)? onUnexpectedError;

  @override
  FutureOr<Response> post(RequestContext context) => fromShelfHandler(
    sessionCommandHandler(
      sessions: sessions,
      id: id,
      commandSerializer: commandSerializer,
      readCredentials: (_) => readCredentials(context),
      onUnexpectedError: onUnexpectedError,
    ),
  )(context);
}

/// Handles WebSocket state subscriptions for a shared state session.
///
/// Each connection authenticates independently. [projectState] must filter
/// the state for its authenticated principal before serialization.
class SessionWebSocketView<State, Credentials, Principal, View> extends _SessionView with GetMixin {
  /// Creates a WebSocket view backed by [sessions].
  SessionWebSocketView({
    required this.sessions,
    required this.id,
    required this.credentialsSerializer,
    required this.stateSerializer,
    required this.projectState,
    this.projectPublicState,
    this.onAuthenticated,
    this.onClosed,
    this.messageSerializer,
    this.sendStateOnPing = false,
    this.allowedOrigins,
    this.pingInterval,
    this.onUnexpectedError,
  });

  /// The shared service that owns the session.
  final StateSessionService<State, Credentials, Principal> sessions;

  /// The session ID obtained from the route.
  final String id;

  /// Decodes credentials from the WebSocket authentication message.
  final Serializer<Credentials> credentialsSerializer;

  /// Encodes the projected view sent to a connection.
  final Serializer<View> stateSerializer;

  /// Selects the state visible to a principal.
  final View Function(State state, Principal principal) projectState;

  /// Selects the public view, or null to require authentication first.
  final View Function(State state)? projectPublicState;

  /// Runs after authentication and before the private state is sent.
  final FutureOr<void> Function(Credentials credentials, Principal principal)? onAuthenticated;

  /// Runs once when the connection closes.
  final FutureOr<void> Function(Principal? principal)? onClosed;

  /// Overrides the default versioned message representation.
  final Serializer<ProtocolMessage>? messageSerializer;

  /// Sends the current visible state after each heartbeat response.
  final bool sendStateOnPing;

  /// The permitted browser origins, or null to leave origins unrestricted.
  final Iterable<String>? allowedOrigins;

  /// The optional WebSocket transport ping interval.
  final Duration? pingInterval;

  /// Receives unexpected failures for server-side logging.
  final void Function(Object error, StackTrace stackTrace)? onUnexpectedError;

  @override
  FutureOr<Response> get(RequestContext context) => fromShelfHandler(
    sessionWebSocketHandler(
      sessions: sessions,
      id: id,
      credentialsSerializer: credentialsSerializer,
      stateSerializer: stateSerializer,
      projectState: projectState,
      projectPublicState: projectPublicState,
      onAuthenticated: onAuthenticated,
      onClosed: onClosed,
      messageSerializer: messageSerializer,
      sendStateOnPing: sendStateOnPing,
      allowedOrigins: allowedOrigins,
      pingInterval: pingInterval,
      onUnexpectedError: onUnexpectedError,
    ),
  )(context);
}
