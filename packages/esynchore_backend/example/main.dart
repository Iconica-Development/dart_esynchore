import "dart:io";

import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_backend/esynchore_backend.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:fpdart/fpdart.dart";
import "package:shelf/shelf.dart";
import "package:shelf/shelf_io.dart" as shelf_io;

class Increment extends StateCommand<int, int> {
  const Increment();

  @override
  String get type => "increment";

  @override
  TaskEither<AuthorizationError, Unit> authorize(int state, int principal) => TaskEither.right(unit);

  @override
  TaskEither<ApplicationError, int> apply(int state, int principal) => TaskEither.right(state + 1);
}

final credentialsSerializer = Serializer<String>(
  fromMap: (map) => map["token"] is String ? map["token"] as String : throw const FormatException("Expected a token."),
  toMap: (credentials) => {"token": credentials},
);

final commandSerializer = Serializer<StateCommand<int, int>>(
  fromMap: (map) => map["type"] == "increment" ? const Increment() : throw const FormatException("Unknown command."),
  toMap: (command) => {"type": command.type},
);

final stateSerializer = Serializer<int>(
  fromMap: (map) =>
      map["value"] is int ? map["value"] as int : throw const FormatException("Expected an integer state."),
  toMap: (state) => {"value": state},
);

Future<void> main() async {
  final sessions = StateSessionService<int, String, int>(
    authenticate: (state, credentials) => credentials == "demo"
        ? TaskEither.right(1)
        : TaskEither.left(
            const AuthenticationError("invalid_credentials", "Invalid credentials."),
          ),
  )..create("main", 0);

  final commands = sessionCommandHandler(
    sessions: sessions,
    id: "main",
    commandSerializer: commandSerializer,
    readCredentials: (request) => request.headers["authorization"] ?? "",
  );
  final state = sessionWebSocketHandler(
    sessions: sessions,
    id: "main",
    credentialsSerializer: credentialsSerializer,
    stateSerializer: stateSerializer,
    projectState: (value, principal) => value,
  );

  final server = await shelf_io.serve(
    (request) => switch (request.url.path) {
      "commands" => commands(request),
      "state" => state(request),
      _ => Response.notFound("Not found"),
    },
    InternetAddress.loopbackIPv4,
    8080,
  );
  stdout.writeln("Listening on http://localhost:${server.port}");
}
