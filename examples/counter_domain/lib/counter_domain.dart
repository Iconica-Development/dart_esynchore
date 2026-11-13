import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:fpdart/fpdart.dart";

class Counters {
  const Counters({this.first = 0, this.second = 0});

  final int first;
  final int second;

  Counters incrementCounter(int counterId, int value) =>
    Counters(first: counterId == 1 ? first + value : first, second: counterId == 2 ? second + value : second);
}

class Increment extends StateCommand<Counters, int> {
  const Increment(this.counter);

  final int counter;

  @override
  String get type => "increment";

  @override
  TaskEither<AuthorizationError, Unit> authorize(Counters state, int principal) => .fromPredicate(
    unit,
    (_) => counter == principal,
    (_) => const AuthorizationError("forbidden", "Cannot modify this counter."),
  );

  @override
  TaskEither<ApplicationError, Counters> apply(Counters state, int principal) =>
      .Do(($) async => state.incrementCounter(counter, 1));
}

TaskEither<AuthenticationError, int> authenticate(Counters state, String credentials) => switch (credentials) {
  "auth:1" => .right(1),
  "auth:2" => .right(2),
  _ => .left(const AuthenticationError("invalid_credentials", "Invalid credentials.")),
};

final credentialsSerializer = Serializer<String>(
  fromMap: (map) => map["auth"] is String ? map["auth"] as String : throw const FormatException("Invalid credentials."),
  toMap: (credentials) => {"auth": credentials},
);

final countersSerializer = Serializer<Counters>(
  fromMap: (map) => map["first"] is int && map["second"] is int
      ? Counters(first: map["first"] as int, second: map["second"] as int)
      : throw const FormatException("Invalid counters."),
  toMap: (state) => {"first": state.first, "second": state.second},
);

final commandSerializer = Serializer<StateCommand<Counters, int>>(
  fromMap: (map) => map["type"] == "increment" && (map["counter"] == 1 || map["counter"] == 2)
      ? Increment(map["counter"] as int)
      : throw const FormatException("Invalid command."),
  toMap: (command) => switch (command) {
    Increment(:final counter) => {"type": command.type, "counter": counter},
    _ => throw const FormatException("Invalid command."),
  },
);
