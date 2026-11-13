/// Framework error codes and their meanings.
///
/// Application-defined codes such as domain validation failures are not
/// included. Use [all] to enumerate framework codes or [describe] to look up
/// a code's description.
sealed class EsynchoreErrorCodes {
  /// The incoming protocol message is malformed or unsupported.
  static const invalidMessage = "invalid_message";

  /// The request payload is invalid.
  static const invalidPayload = "invalid_payload";

  /// The request could not be processed due to an unexpected error.
  static const internalError = "internal_error";

  /// The message is not valid for this endpoint.
  static const unexpectedMessage = "unexpected_message";

  /// The WebSocket connection is already authenticated.
  static const alreadyAuthenticated = "already_authenticated";

  /// The current state could not be projected or serialized.
  static const stateEncodingFailed = "state_encoding_failed";

  /// The state handler has started closing and rejects new operations.
  static const actionOnClosedConnection = "action_on_closed_connection";

  /// The request did not receive a response before the timeout.
  static const timeout = "timeout";

  /// The server response did not match the request.
  static const invalidResponse = "invalid_response";

  /// The transport disconnected before the request completed.
  static const disconnected = "disconnected";

  /// The HTTP command endpoint returned an unrecognized error response.
  static const httpError = "http_error";

  /// The requested state session does not exist.
  static const sessionNotFound = "session_not_found";

  /// Every framework-defined error code.
  static const List<String> all = [
    invalidMessage,
    invalidPayload,
    internalError,
    unexpectedMessage,
    alreadyAuthenticated,
    stateEncodingFailed,
    actionOnClosedConnection,
    timeout,
    invalidResponse,
    disconnected,
    httpError,
    sessionNotFound,
  ];

  /// Human-readable meaning for each framework-defined code.
  static const Map<String, String> descriptions = {
    invalidMessage: "The incoming protocol message is malformed or unsupported.",
    invalidPayload: "The request payload is invalid.",
    internalError: "The request could not be processed due to an unexpected error.",
    unexpectedMessage: "The message is not valid for this endpoint.",
    alreadyAuthenticated: "The WebSocket connection is already authenticated.",
    stateEncodingFailed: "The current state could not be projected or serialized.",
    actionOnClosedConnection: "The state handler has started closing and rejects new operations.",
    timeout: "The request did not receive a response before the timeout.",
    invalidResponse: "The server returned a response that did not match the request.",
    disconnected: "The transport disconnected before the request completed.",
    httpError: "The HTTP command endpoint returned an unrecognized error response.",
    sessionNotFound: "The requested state session does not exist.",
  };

  /// Returns the framework description for [code], or null for custom codes.
  static String? describe(String code) => descriptions[code];
}

/// An expected failure while authenticating or processing a command.
///
/// The application may use [code] and [details] to distinguish and describe
/// domain-specific failures without defining another error hierarchy.
sealed class EsynchoreError {
  /// Creates an error with an application-defined code and message.
  const EsynchoreError(this.code, this.message, {this.details});

  /// A stable, application-defined identifier for the failure.
  final String code;

  /// A description of the failure.
  final String message;

  /// Optional application-defined context for the failure.
  ///
  /// Applications are responsible for removing sensitive data before sending
  /// this value or [message] to a client.
  final Object? details;

  @override
  String toString() => "EsynchoreError($code): $message";
}

/// Credentials could not be resolved to a principal.
final class AuthenticationError extends EsynchoreError {
  /// Creates an authentication failure.
  const AuthenticationError(super.code, super.message, {super.details});
}

/// A principal is not permitted to execute a command.
final class AuthorizationError extends EsynchoreError {
  /// Creates an authorization failure.
  const AuthorizationError(super.code, super.message, {super.details});
}

/// A command could not be applied to the current state.
final class ApplicationError extends EsynchoreError {
  /// Creates an application failure.
  const ApplicationError(super.code, super.message, {super.details});
}
