import "dart:async";

import "package:counter_domain/counter_domain.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:test/test.dart";

void main() {
  test(
    "credentials can watch both counters but only change their own",
    () async {
      final handler = StateHandler<Counters, String, int>(
        initialState: const Counters(),
        authenticate: authenticate,
      );
      expect((await handler.openSession("invalid").run()).isLeft(), isTrue);
      final first = (await handler.openSession("auth:1").run()).getRight().toNullable()!;
      final second = (await handler.openSession("auth:2").run()).getRight().toNullable()!;
      expect((await first.submit(const Increment(2)).run()).isLeft(), isTrue);
      expect((await second.submit(const Increment(1)).run()).isLeft(), isTrue);
      expect((await first.submit(const Increment(1)).run()).isRight(), isTrue);
      expect((await second.submit(const Increment(2)).run()).isRight(), isTrue);
      expect(countersSerializer.toMap(handler.state), {
        "first": 1,
        "second": 1,
      });
      expect(
        commandSerializer.fromMap({"type": "increment", "counter": 2}),
        isA<Increment>(),
      );
      expect(
        () => commandSerializer.fromMap({"type": "increment", "counter": 3}),
        throwsFormatException,
      );
      await handler.close();
    },
  );

  test(
    "orders authentication and observations and drains pending submissions",
    () async {
      final gate = Completer<void>();
      final authenticationStates = <int>[];
      final appliedStates = <int>[];
      final errors = <Object>[];
      final handler = StateHandler<Counters, String, int>(
        initialState: const Counters(),
        authenticate: (state, credentials) => .Do(($) async {
          authenticationStates.add(state.first);
          if (credentials == "slow") await gate.future;
          return $(authenticate(state, "auth:1"));
        }),
        onApplied: (command, principal, state) {
          appliedStates.add(state.first);
          if (state.first == 1) throw StateError("observer failed");
        },
        onObserverError: (error, stackTrace) => errors.add(error),
      );
      final first = handler.submit(const Increment(1), "slow");
      final second = handler.submit(const Increment(1), "next");
      final closing = handler.close();
      gate.complete();

      expect((await first.run()).isRight(), isTrue);
      expect((await second.run()).isRight(), isTrue);
      await closing;
      expect(authenticationStates, [0, 1]);
      expect(appliedStates, [1, 2]);
      expect(errors.single, isA<StateError>());
      expect(handler.state.first, 2);
    },
  );

  test(
    "projects public and authenticated state and closes its lifecycle",
    () async {
      final authenticationStarted = Completer<void>();
      final finishAuthentication = Completer<void>();
      final handler = StateHandler<Counters, String, int>(
        initialState: const Counters(first: 1, second: 42),
        authenticate: (state, credentials) => .Do(
          ($) async {
            if (credentials == "slow") {
              authenticationStarted.complete();
              await finishAuthentication.future;
              return $(authenticate(state, "invalid"));
            }
            return $(authenticate(state, credentials));
          },
        ),
      );
      final connected = <int>[];
      final disconnected = <int?>[];
      final session = ProtocolServerSession<Counters, String, int, Counters>(
        handler: handler,
        credentialsSerializer: credentialsSerializer,
        stateSerializer: countersSerializer,
        projectPublicState: (state) => Counters(first: state.first),
        projectState: (state, principal) => state,
        onAuthenticated: (credentials, principal) => connected.add(principal),
        onClosed: disconnected.add,
        sendStateOnPing: true,
      );
      final messages = StreamIterator(session.outgoing);
      Future<ProtocolMessage> next() async {
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        return ProtocolMessage.decode(messages.current);
      }

      final initialState = next();
      session.start();
      expect((await initialState as StateMessage).state, {
        "first": 1,
        "second": 0,
      });
      expect(await next(), isA<AuthenticationRequiredMessage>());
      await session.receive(
        const AuthenticateMessage("bad", {"auth": "invalid"}).encode(),
      );
      expect(await next(), isA<ErrorMessage>());
      final publicUpdate = next();
      await handler.submit(const Increment(1), "auth:1").run();
      expect((await publicUpdate as StateMessage).state, {
        "first": 2,
        "second": 0,
      });
      final pendingAuthentication = session.receive(
        const AuthenticateMessage("slow", {"auth": "slow"}).encode(),
      );
      await authenticationStarted.future;
      final statePublished = handler.stateChanges.first;
      await handler.submit(const Increment(1), "auth:1").run();
      await statePublished;
      finishAuthentication.complete();
      await pendingAuthentication;
      expect(await next(), isA<ErrorMessage>());
      expect((await next() as StateMessage).state, {"first": 3, "second": 0});
      await session.receive(
        const AuthenticateMessage("good", {"auth": "auth:1"}).encode(),
      );
      expect(await next(), isA<AuthenticatedMessage>());
      expect((await next() as StateMessage).state, {"first": 3, "second": 42});
      await session.receive(const PingMessage("ping").encode());
      expect(await next(), isA<PongMessage>());
      expect(await next(), isA<StateMessage>());
      expect(connected, [1]);

      await messages.cancel();
      await session.close();
      await handler.close();
      expect(disconnected, [1]);
    },
  );
}
