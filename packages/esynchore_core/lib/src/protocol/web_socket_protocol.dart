import "dart:async";

import "package:esynchore_core/src/protocol/protocol_client.dart";
import "package:esynchore_core/src/protocol/protocol_server.dart";
import "package:web_socket_channel/web_socket_channel.dart";

/// Binds a protocol endpoint to a WebSocket channel.
///
/// Closing the connection also closes the endpoint and channel. Unexpected
/// transport or decoding failures are reported through [onError] before the
/// connection closes. This class does not reconnect automatically.
class WebSocketProtocolConnection {
  WebSocketProtocolConnection._(
    this._channel,
    Stream<String> outgoing,
    this._receive,
    this._closeEndpoint,
    this.onError,
  ) {
    _outgoingSubscription = outgoing.listen(_send, onError: _fail);
    _incomingSubscription = _channel.stream.listen(
      _incoming,
      onError: _fail,
      onDone: _disconnected,
    );
  }

  /// Connects a client protocol endpoint to [channel].
  ///
  /// Await the channel's `ready` future before sending requests. Callers must
  /// use a fresh endpoint for each connection.
  static WebSocketProtocolConnection client<Credentials, View>(
    WebSocketChannel channel,
    ProtocolClient<Credentials, View> client, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) => WebSocketProtocolConnection._(
    channel,
    client.outgoing,
    client.receive,
    client.close,
    onError,
  );

  /// Connects a server protocol endpoint to an accepted WebSocket [channel].
  static WebSocketProtocolConnection server<State, Credentials, Principal, View>(
    WebSocketChannel channel,
    ProtocolServerSession<State, Credentials, Principal, View> session, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) => WebSocketProtocolConnection._(
    channel,
    session.outgoing,
    session.receive,
    session.close,
    onError,
  );

  final WebSocketChannel _channel;
  final FutureOr<void> Function(String frame) _receive;
  final Future<void> Function() _closeEndpoint;

  /// Receives unexpected transport or protocol failures.
  final void Function(Object error, StackTrace stackTrace)? onError;

  late final StreamSubscription<String> _outgoingSubscription;
  late final StreamSubscription<dynamic> _incomingSubscription;
  final Completer<void> _done = Completer<void>();
  Future<void>? _closing;

  /// Completes when the connection has finished closing.
  Future<void> get done => _done.future;

  void _send(String frame) {
    try {
      _channel.sink.add(frame);
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _incoming(dynamic frame) {
    if (frame is! String) {
      _fail(
        const FormatException("Expected a WebSocket text frame."),
        StackTrace.current,
      );
      return;
    }
    unawaited(Future<void>.sync(() => _receive(frame)).catchError(_fail));
  }

  void _fail(Object error, StackTrace stackTrace) {
    try {
      onError?.call(error, stackTrace);
    } finally {
      unawaited(close());
    }
  }

  void _disconnected() => unawaited(close());

  /// Closes the connection and releases its protocol subscriptions.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _incomingSubscription.cancel();
      await _closeEndpoint();
      await _outgoingSubscription.cancel();
      await _channel.sink.close();
    } finally {
      _done.complete();
    }
  }
}
