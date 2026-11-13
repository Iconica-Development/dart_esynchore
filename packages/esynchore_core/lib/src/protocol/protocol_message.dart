import "dart:convert";

import "package:dart_iconica_utilities/dart_iconica_utilities.dart";

/// Serializes versioned protocol messages to and from JSON objects.
final protocolMessageSerializer = Serializer<ProtocolMessage>(
  toMap: (message) => {"version": ProtocolMessage.version, ...message.toMap()},
  fromMap: ProtocolMessage.fromMap,
);

/// A versioned message exchanged between an Esynchore client and server.
///
/// Application payloads must contain JSON-encodable values. The transport is
/// responsible for carrying each encoded message as a separate text frame.
sealed class ProtocolMessage {
  /// Creates a protocol message.
  const ProtocolMessage();

  /// The current wire protocol version.
  static const int version = 1;

  /// Encodes this message as a JSON text frame.
  String encode() => jsonEncode(protocolMessageSerializer.toMap(this));

  /// Returns this message's fields without the protocol version.
  Map<String, Object?> toMap();

  /// Decodes a JSON text frame.
  ///
  /// Throws [FormatException] for unsupported versions, unknown message types,
  /// or invalid fields.
  static ProtocolMessage decode(String frame) {
    final decoded = jsonDecode(frame);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("A protocol message must be an object.");
    }
    return protocolMessageSerializer.fromMap(decoded);
  }

  /// Decodes a versioned protocol message from a JSON object.
  static ProtocolMessage fromMap(Map<String, dynamic> decoded) {
    if (decoded["version"] != version) {
      throw const FormatException("Unsupported protocol version.");
    }
    final type = _string(decoded, "type");
    return switch (type) {
      "authenticate" => AuthenticateMessage(
        _id(decoded),
        _object(decoded, "credentials"),
      ),
      "authentication_required" => const AuthenticationRequiredMessage(),
      "authenticated" => AuthenticatedMessage(_id(decoded)),
      "state" => StateMessage(_object(decoded, "state")),
      "error" => ErrorMessage(
        requestId: _optionalId(decoded),
        category:
            ProtocolErrorCategory.values.where((value) => value.name == decoded["category"]).firstOrNull ??
            (throw const FormatException("Unknown error category.")),
        code: _string(decoded, "code"),
        message: _string(decoded, "message"),
        details: decoded["details"],
      ),
      "ping" => PingMessage(_id(decoded)),
      "pong" => PongMessage(_id(decoded)),
      _ => throw FormatException("Unknown protocol message type: $type"),
    };
  }
}

String _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw FormatException("Expected a non-empty string for $key.");
  }
  return value;
}

String _id(Map<String, dynamic> map) => _string(map, "requestId");

String? _optionalId(Map<String, dynamic> map) => map["requestId"] == null ? null : _id(map);

Map<String, dynamic> _object(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException("Expected an object for $key.");
  }
  return value;
}

/// Announces that a connection may authenticate for a private state view.
final class AuthenticationRequiredMessage extends ProtocolMessage {
  /// Creates an authentication prompt.
  const AuthenticationRequiredMessage();

  @override
  Map<String, Object?> toMap() => {"type": "authentication_required"};
}

/// Requests authentication with an application-defined credentials payload.
final class AuthenticateMessage extends ProtocolMessage {
  /// Creates an authentication request.
  const AuthenticateMessage(this.requestId, this.credentials);

  /// Correlates the response with this request.
  final String requestId;

  /// Credentials encoded by the application.
  final Map<String, dynamic> credentials;

  @override
  Map<String, Object?> toMap() => {
    "type": "authenticate",
    "requestId": requestId,
    "credentials": credentials,
  };
}

/// Confirms that authentication succeeded.
final class AuthenticatedMessage extends ProtocolMessage {
  /// Creates an authentication acknowledgement.
  const AuthenticatedMessage(this.requestId);

  /// The corresponding authentication request.
  final String requestId;

  @override
  Map<String, Object?> toMap() => {
    "type": "authenticated",
    "requestId": requestId,
  };
}

/// Publishes a recipient-specific representation of the current state.
final class StateMessage extends ProtocolMessage {
  /// Creates a state update.
  const StateMessage(this.state);

  /// The state encoded for this recipient.
  final Map<String, dynamic> state;

  @override
  Map<String, Object?> toMap() => {"type": "state", "state": state};
}

/// Identifies the stage at which a request failed.
enum ProtocolErrorCategory {
  /// A message or protocol operation was invalid.
  protocol,

  /// Credentials were rejected.
  authentication,

  /// The principal was not allowed to perform a command.
  authorization,

  /// The command could not be applied to the state.
  application,
}

/// Reports an expected failure or a protocol-level error.
final class ErrorMessage extends ProtocolMessage {
  /// Creates an error response.
  const ErrorMessage({
    required this.category,
    required this.code,
    required this.message,
    this.requestId,
    this.details,
  });

  /// The related request, or null when the frame could not be identified.
  final String? requestId;

  /// The stage at which the failure occurred.
  final ProtocolErrorCategory category;

  /// A stable identifier for the failure.
  final String code;

  /// A description suitable for the recipient.
  final String message;

  /// Optional JSON-encodable details suitable for the recipient.
  final Object? details;

  @override
  Map<String, Object?> toMap() => {
    "type": "error",
    if (requestId != null) "requestId": requestId,
    "category": category.name,
    "code": code,
    "message": message,
    if (details != null) "details": details,
  };
}

/// Requests a heartbeat response.
final class PingMessage extends ProtocolMessage {
  /// Creates a heartbeat request.
  const PingMessage(this.requestId);

  /// Correlates the response with this request.
  final String requestId;

  @override
  Map<String, Object?> toMap() => {"type": "ping", "requestId": requestId};
}

/// Answers a heartbeat request.
final class PongMessage extends ProtocolMessage {
  /// Creates a heartbeat response.
  const PongMessage(this.requestId);

  /// The corresponding heartbeat request.
  final String requestId;

  @override
  Map<String, Object?> toMap() => {"type": "pong", "requestId": requestId};
}
