import "dart:async";
import "dart:convert";

import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_core/src/models/esynchore_error.dart";
import "package:esynchore_core/src/protocol/protocol_message.dart";
import "package:fpdart/fpdart.dart";

/// A client-side protocol session for a single transport connection.
///
/// Subscribe to [outgoing] before making requests, forward incoming text
/// frames to [receive], and call [close] when the transport disconnects.
/// Authentication and authorization are enforced by the server.
class ProtocolClient<Credentials, View> {
  /// Creates a protocol client with application-provided serializers.
  ProtocolClient({
    required this.credentialsSerializer,
    required this.stateSerializer,
    this.messageSerializer,
    this.requestTimeout = const Duration(seconds: 30),
  });

  /// Encodes credentials sent to the server.
  final Serializer<Credentials> credentialsSerializer;

  /// Decodes recipient-specific state updates.
  final Serializer<View> stateSerializer;

  /// Overrides the default versioned protocol's message representation.
  final Serializer<ProtocolMessage>? messageSerializer;

  /// The maximum time to wait for an individual response.
  final Duration requestTimeout;

  final StreamController<String> _outgoing = StreamController.broadcast();
  final StreamController<View> _states = StreamController.broadcast();
  final StreamController<ErrorMessage> _errors = StreamController.broadcast();
  final Map<String, _PendingRequest> _pending = {};
  int _nextId = 0;
  bool _closed = false;
  Future<void>? _closing;

  /// JSON text frames to send to the server.
  Stream<String> get outgoing => _outgoing.stream;

  /// State views received from the server after authentication.
  Stream<View> get stateChanges => _states.stream;

  /// Errors that are not correlated with an outstanding request.
  Stream<ErrorMessage> get errors => _errors.stream;

  /// Authenticates this connection using [credentials].
  Future<Either<ErrorMessage, Unit>> authenticate(Credentials credentials) {
    _checkOpen();
    final requestId = _newId();
    return _request(
      AuthenticateMessage(requestId, credentialsSerializer.toMap(credentials)),
      requestId,
      "authenticated",
    );
  }

  /// Requests a heartbeat response from the server.
  Future<Either<ErrorMessage, Unit>> ping() {
    _checkOpen();
    final requestId = _newId();
    return _request(PingMessage(requestId), requestId, "pong");
  }

  /// Processes a text frame received from the server.
  ///
  /// Throws [FormatException] for invalid or unexpected messages, or
  /// [StateError] after the client is closed. State decoding errors are
  /// propagated to the caller.
  void receive(String frame) {
    _checkOpen();
    final decoded = jsonDecode(frame);
    if (decoded is! Map<String, dynamic>) throw const FormatException("Expected a protocol object.");
    final message = (messageSerializer ?? protocolMessageSerializer).fromMap(
      decoded,
    );
    switch (message) {
      case AuthenticationRequiredMessage():
        break;
      case StateMessage(:final state):
        _states.add(stateSerializer.fromMap(state));
      case ErrorMessage(:final requestId):
        final pending = requestId == null ? null : _pending.remove(requestId);
        if (pending == null) {
          _errors.add(message);
        } else {
          pending.complete(Left(message));
        }
      case AuthenticatedMessage(:final requestId):
        _acknowledge(requestId, "authenticated");
      case PongMessage(:final requestId):
        _acknowledge(requestId, "pong");
      case _:
        throw const FormatException("This message cannot be sent to a client.");
    }
  }

  String _newId() => (++_nextId).toString();

  Future<Either<ErrorMessage, Unit>> _request(
    ProtocolMessage message,
    String requestId,
    String expected,
  ) {
    final frame = jsonEncode(
      (messageSerializer ?? protocolMessageSerializer).toMap(message),
    );
    final completer = Completer<Either<ErrorMessage, Unit>>();
    final timer = Timer(requestTimeout, () {
      _pending
          .remove(requestId)
          ?.complete(
            Left(
              _protocolError(
                requestId,
                EsynchoreErrorCodes.timeout,
                "The request timed out.",
              ),
            ),
          );
    });
    _pending[requestId] = _PendingRequest(expected, completer, timer);
    _outgoing.add(frame);
    return completer.future;
  }

  void _acknowledge(String requestId, String type) {
    final pending = _pending.remove(requestId);
    if (pending == null) return;
    if (pending.expected != type) {
      pending.complete(
        Left(
          _protocolError(
            requestId,
            EsynchoreErrorCodes.invalidResponse,
            "Unexpected response to request.",
          ),
        ),
      );
    } else {
      pending.complete(const Right(unit));
    }
  }

  ErrorMessage _protocolError(String requestId, String code, String message) => ErrorMessage(
    requestId: requestId,
    category: ProtocolErrorCategory.protocol,
    code: code,
    message: message,
  );

  /// Fails requests from a disconnected transport without closing the client.
  ///
  /// A transport that reconnects can call this before sending new requests.
  void disconnected() {
    _checkOpen();
    _failPendingRequests();
  }

  /// Stops the client and completes pending requests with a protocol error.
  ///
  /// The transport remains responsible for closing its own connection.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _failPendingRequests();
    await Future.wait([_outgoing.close(), _states.close(), _errors.close()]);
  }

  void _failPendingRequests() {
    for (final entry in _pending.entries) {
      entry.value.complete(
        Left(
          _protocolError(
            entry.key,
            EsynchoreErrorCodes.disconnected,
            "The connection closed.",
          ),
        ),
      );
    }
    _pending.clear();
  }

  void _checkOpen() {
    if (_closed) throw StateError("The protocol client is closed.");
  }
}

class _PendingRequest {
  _PendingRequest(this.expected, this.completer, this.timer);

  final String expected;
  final Completer<Either<ErrorMessage, Unit>> completer;
  final Timer timer;

  void complete(Either<ErrorMessage, Unit> result) {
    timer.cancel();
    completer.complete(result);
  }
}
