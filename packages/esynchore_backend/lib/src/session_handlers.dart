import "dart:async";

import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_backend/src/http_command_handler.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:shelf/shelf.dart";
import "package:shelf_web_socket/shelf_web_socket.dart";

/// Creates an HTTP command handler for a session in [sessions].
///
/// Resolve the session ID from the application's route and supply it as [id].
/// Missing or closing sessions return a protocol error with HTTP status 404.
Handler sessionCommandHandler<State, Credentials, Principal>({
  required StateSessionService<State, Credentials, Principal> sessions,
  required String id,
  required Serializer<StateCommand<State, Principal>> commandSerializer,
  required FutureOr<Credentials> Function(Request request) readCredentials,
  Response Function(EsynchoreError error)? failureResponse,
  Response Function(FormatException error)? invalidRequestResponse,
  Response Function()? sessionNotFoundResponse,
  bool readCredentialsAfterCommand = false,
  void Function(Object error, StackTrace stackTrace)? onUnexpectedError,
}) => (request) {
  final handler = sessions.get(id);
  if (handler == null) return sessionNotFoundResponse?.call() ?? _sessionNotFound();
  return httpCommandHandler(
    handler: handler,
    commandSerializer: commandSerializer,
    readCredentials: readCredentials,
    failureResponse: failureResponse,
    invalidRequestResponse: invalidRequestResponse,
    readCredentialsAfterCommand: readCredentialsAfterCommand,
    onUnexpectedError: onUnexpectedError,
  )(request);
};

/// Creates a WebSocket state protocol handler for a session in [sessions].
///
/// Each connection authenticates independently. [projectState] must omit any
/// state the authenticated principal is not entitled to see. Applications
/// should restrict browser origins using [allowedOrigins] where appropriate.
Handler sessionWebSocketHandler<State, Credentials, Principal, View>({
  required StateSessionService<State, Credentials, Principal> sessions,
  required String id,
  required Serializer<Credentials> credentialsSerializer,
  required Serializer<View> stateSerializer,
  required View Function(State state, Principal principal) projectState,
  View Function(State state)? projectPublicState,
  FutureOr<void> Function(Credentials credentials, Principal principal)? onAuthenticated,
  FutureOr<void> Function(Principal? principal)? onClosed,
  Serializer<ProtocolMessage>? messageSerializer,
  bool sendStateOnPing = false,
  Iterable<String>? allowedOrigins,
  Duration? pingInterval,
  void Function(Object error, StackTrace stackTrace)? onUnexpectedError,
}) => sessionWebSocketHandlerFromFactory(
  sessions: sessions,
  id: id,
  createSession: (handler) => ProtocolServerSession<State, Credentials, Principal, View>(
    handler: handler,
    credentialsSerializer: credentialsSerializer,
    stateSerializer: stateSerializer,
    projectState: projectState,
    projectPublicState: projectPublicState,
    onAuthenticated: onAuthenticated,
    onClosed: onClosed,
    messageSerializer: messageSerializer,
    sendStateOnPing: sendStateOnPing,
    onUnexpectedError: onUnexpectedError,
  ),
  allowedOrigins: allowedOrigins,
  pingInterval: pingInterval,
  onUnexpectedError: onUnexpectedError,
);

/// Creates a WebSocket handler with a separate protocol session per connection.
///
/// Use [createSession] when projections, codecs, or lifecycle hooks require
/// connection-local state. The factory must use the supplied state handler.
/// [onStarted] runs after the session subscribes and starts publishing.
Handler sessionWebSocketHandlerFromFactory<State, Credentials, Principal, View>({
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
  Response Function()? sessionNotFoundResponse,
  Iterable<String>? allowedOrigins,
  Duration? pingInterval,
  void Function(Object error, StackTrace stackTrace)? onUnexpectedError,
}) => (request) {
  final handler = sessions.get(id);
  if (handler == null) return sessionNotFoundResponse?.call() ?? _sessionNotFound();
  return webSocketHandler(
    (channel, _) {
      final session = createSession(handler);
      if (!identical(session.handler, handler)) {
        unawaited(channel.sink.close());
        throw StateError(
          "The protocol session must use the registered state handler.",
        );
      }
      onConnectionOpened?.call();
      final connection = WebSocketProtocolConnection.server(
        channel,
        session,
        onError: onUnexpectedError,
      );
      session.start();
      onStarted?.call(session);
      final stateSubscription = handler.stateChanges.listen(
        (_) {},
        onDone: () => unawaited(connection.close()),
      );
      unawaited(connection.done.then((_) => stateSubscription.cancel()));
    },
    allowedOrigins: allowedOrigins,
    pingInterval: pingInterval,
  )(request);
};

Response _sessionNotFound() => Response.notFound(
  const ErrorMessage(
    category: ProtocolErrorCategory.protocol,
    code: EsynchoreErrorCodes.sessionNotFound,
    message: "The requested session does not exist.",
  ).encode(),
  headers: {"content-type": "application/json"},
);
