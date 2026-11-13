# esynchore_core

Core state coordination and protocol primitives for Esynchore. Use this
package to define immutable state transitions, authenticate sessions, and
stream principal-specific state over WebSockets.

Commands are submitted through an application-owned channel, such as the HTTP
adapter in [`esynchore_backend`](../esynchore_backend/README.md). The WebSocket
protocol is for authentication, state updates, and heartbeats; it does not
carry commands.

## Install

```sh
dart pub add esynchore_core
```

## State and commands

Implement `StateCommand<State, Principal>` for each state transition. A
`StateHandler` authorizes and applies commands in submission order, publishing
each successfully applied state to `stateChanges`.

```dart
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
  (error) => print("Command rejected: ${error.message}"),
  (state) => print("Current value: $state"),
);

await handler.close();
```

`Increment` in this snippet is an application-defined `StateCommand`. See
[`example/main.dart`](example/main.dart) for its implementation and imports.

## Sessions and protocol

Use `StateSessionService` to own multiple named handlers in one server
process. Create one `ProtocolServerSession` per WebSocket connection, and use
`ProtocolClient` on clients. `WebSocketProtocolConnection` binds either
endpoint to a `web_socket_channel`.

Always filter server state with `projectState` before serialization; clients
must not receive information their principal is not allowed to see. State
objects should be immutable. The in-memory session service is process-local
and does not coordinate across isolates or server instances.

## Error codes

Framework-defined errors are listed in `EsynchoreErrorCodes.all` and described
by `EsynchoreErrorCodes.descriptions`. Use `EsynchoreErrorCodes.describe(code)`
to look up one description. Applications can define additional
authentication, authorization, and application error codes.

## Compatibility

Requires Dart 3.13.3 or later.
