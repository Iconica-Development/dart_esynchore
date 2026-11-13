// ignore_for_file: avoid_print

import "package:esynchore_core/esynchore_core.dart";
import "package:fpdart/fpdart.dart";

export "package:dart_iconica_utilities/dart_iconica_utilities.dart";

class Increment extends StateCommand<int, int> {
  const Increment();

  @override
  String get type => "increment";

  @override
  TaskEither<AuthorizationError, Unit> authorize(int state, int principal) => TaskEither.right(unit);

  @override
  TaskEither<ApplicationError, int> apply(int state, int principal) => TaskEither.right(state + 1);
}

Future<void> main() async {
  final handler = StateHandler<int, String, int>(
    initialState: 0,
    authenticate: (state, credentials) => credentials == "demo"
        ? TaskEither.right(1)
        : TaskEither.left(
            const AuthenticationError("invalid_credentials", "Invalid credentials."),
          ),
  );
  final session = (await handler.openSession("demo").run()).match(
    (error) => throw StateError(error.message),
    (session) => session,
  );
  final result = await session.submit(const Increment()).run();
  result.match(
    (error) => throw StateError(error.message),
    (state) => print("Current state: $state"),
  );
  await handler.close();
}
