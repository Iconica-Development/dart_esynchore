import "dart:convert";

import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:fpdart/fpdart.dart";
import "package:http/http.dart" as http;

/// A failed HTTP command and its original transport response.
class HttpCommandFailure {
  /// Creates a failure with its protocol error and HTTP response.
  const HttpCommandFailure({required this.error, required this.response});

  /// The decoded or synthesized protocol error.
  final ErrorMessage error;

  /// The original response, including its status, headers, and body.
  final http.Response response;
}

/// Submits serialized commands over HTTP independently of state streaming.
///
/// The corresponding server must authenticate each request. The caller owns
/// the WebSocket connection used for state updates and heartbeats.
class HttpCommandClient<Credentials, Command> {
  /// Creates a client for [endpoint] with application-provided credentials.
  ///
  /// [headersForCredentials] should return the headers expected by the server.
  /// An injected [client] remains owned by the caller; otherwise [close]
  /// releases the HTTP client created here.
  HttpCommandClient({
    required this.endpoint,
    required this.commandSerializer,
    required this.headersForCredentials,
    this.ensureJsonContentType = true,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// The HTTP endpoint that accepts commands for one shared state.
  final Uri endpoint;

  /// Encodes commands as JSON objects.
  final Serializer<Command> commandSerializer;

  /// Creates request headers from credentials for each submission.
  final Map<String, String> Function(Credentials credentials) headersForCredentials;

  /// Adds a JSON content type if the supplied headers do not already have one.
  final bool ensureJsonContentType;

  final http.Client _client;
  final bool _ownsClient;

  /// Sends [command] with [credentials] and returns the server's result.
  ///
  /// Expected server failures are returned as [ErrorMessage]. A non-Esynchore
  /// HTTP error is returned as a protocol error. Network, encoding, and
  /// credential-provider exceptions are propagated to the caller.
  Future<Either<ErrorMessage, Unit>> submit(
    Command command,
    Credentials credentials,
  ) async => (await submitWithResponse(
    command,
    credentials,
  )).mapLeft((failure) => failure.error);

  /// Sends a command and retains the original response on failure.
  ///
  /// This is useful when adapting an existing HTTP error contract. Network,
  /// encoding, and credential-provider exceptions are propagated to the caller.
  Future<Either<HttpCommandFailure, Unit>> submitWithResponse(
    Command command,
    Credentials credentials,
  ) async {
    final headers = Map<String, String>.from(
      headersForCredentials(credentials),
    );
    if (ensureJsonContentType && !headers.keys.any((key) => key.toLowerCase() == "content-type")) {
      headers["content-type"] = "application/json";
    }
    final response = await _client.post(
      endpoint,
      headers: headers,
      body: jsonEncode(commandSerializer.toMap(command)),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const Right(unit);
    }
    try {
      final message = ProtocolMessage.decode(response.body);
      if (message is ErrorMessage) return Left(HttpCommandFailure(error: message, response: response));
    } on FormatException {
      return Left(_httpFailure(response));
    }
    return Left(_httpFailure(response));
  }

  HttpCommandFailure _httpFailure(http.Response response) => HttpCommandFailure(
    response: response,
    error: ErrorMessage(
      category: ProtocolErrorCategory.protocol,
      code: EsynchoreErrorCodes.httpError,
      message: "HTTP request failed with status ${response.statusCode}.",
    ),
  );

  /// Closes the internally created HTTP client, if any.
  void close() {
    if (_ownsClient) _client.close();
  }
}
