import "dart:async";
import "dart:convert";

import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:shelf/shelf.dart";

/// Creates a Shelf handler that authenticates and applies HTTP commands.
///
/// Mount the returned handler at the command URL for [handler]'s state. Each
/// POST contains a JSON command object decoded by [commandSerializer].
/// [readCredentials] obtains credentials from the individual request, such as
/// its authorization headers; it must not trust a client-supplied principal.
///
/// Success returns HTTP 204. Invalid input returns 400, authentication failure
/// 401, authorization failure 403, and application failure 409. Errors are
/// encoded using the versioned Esynchore protocol message serializer. State
/// updates are delivered separately through the shared [handler].
/// [failureResponse] and [invalidRequestResponse] may override the default
/// error format. Set [readCredentialsAfterCommand] to validate the command
/// before obtaining credentials.
Handler httpCommandHandler<State, Credentials, Principal>({
  required StateHandler<State, Credentials, Principal> handler,
  required Serializer<StateCommand<State, Principal>> commandSerializer,
  required FutureOr<Credentials> Function(Request request) readCredentials,
  Response Function(EsynchoreError error)? failureResponse,
  Response Function(FormatException error)? invalidRequestResponse,
  bool readCredentialsAfterCommand = false,
  void Function(Object error, StackTrace stackTrace)? onUnexpectedError,
}) => (request) async {
  if (request.method != "POST") {
    return Response(405, headers: {"allow": "POST"});
  }

  try {
    late final Credentials credentials;
    if (!readCredentialsAfterCommand) credentials = await readCredentials(request);
    final body = jsonDecode(await request.readAsString());
    if (body is! Map<String, dynamic>) {
      throw const FormatException("Expected a JSON object");
    }
    final command = commandSerializer.fromMap(body);
    if (readCredentialsAfterCommand) credentials = await readCredentials(request);
    final result = await handler.submit(command, credentials).run();
    return await result.match(
      failureResponse ?? _failure,
      (_) => Response(204),
    );
  } on FormatException catch (error) {
    if (invalidRequestResponse != null) return invalidRequestResponse(error);
    return _error(
      400,
      ProtocolErrorCategory.protocol,
      EsynchoreErrorCodes.invalidPayload,
      "Invalid request payload.",
    );
  } on Object catch (error, stackTrace) {
    onUnexpectedError?.call(error, stackTrace);
    return _error(
      500,
      ProtocolErrorCategory.protocol,
      EsynchoreErrorCodes.internalError,
      "The request could not be processed.",
    );
  }
};

Response _failure(EsynchoreError error) => switch (error) {
  AuthenticationError() => _error(
    401,
    ProtocolErrorCategory.authentication,
    error.code,
    error.message,
    error.details,
  ),
  AuthorizationError() => _error(
    403,
    ProtocolErrorCategory.authorization,
    error.code,
    error.message,
    error.details,
  ),
  ApplicationError() => _error(
    409,
    ProtocolErrorCategory.application,
    error.code,
    error.message,
    error.details,
  ),
};

Response _error(int status, ProtocolErrorCategory category, String code, String message, [Object? details]) => Response(
  status,
  body: ErrorMessage(
    category: category,
    code: code,
    message: message,
    details: details,
  ).encode(),
  headers: {"content-type": "application/json"},
);
