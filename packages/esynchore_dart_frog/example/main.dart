import "package:dart_frog/dart_frog.dart";
import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:esynchore_dart_frog/esynchore_dart_frog.dart";
import "package:fpdart/fpdart.dart";

class Increment extends StateCommand<int, int> {
  const Increment();

  @override
  String get type => "increment";

  @override
  TaskEither<AuthorizationError, Unit> authorize(int state, int principal) => .right(unit);

  @override
  TaskEither<ApplicationError, int> apply(int state, int principal) => .right(state + 1);
}

final sessions = StateSessionService<int, String, int>(
  authenticate: (state, credentials) => credentials == "demo"
      ? .right(1)
      : .left(
          const AuthenticationError("invalid_credentials", "Invalid credentials."),
        ),
)..create("main", 0);

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

Future<Response> stateRoute(RequestContext context) => SessionWebSocketView(
  sessions: sessions,
  id: "main",
  credentialsSerializer: credentialsSerializer,
  stateSerializer: stateSerializer,
  projectState: (state, principal) => state,
).asView(context);

Future<Response> commandRoute(RequestContext context) => SessionCommandView(
  sessions: sessions,
  id: "main",
  commandSerializer: commandSerializer,
  readCredentials: (context) => context.request.headers["authorization"] ?? "",
).asView(context);
