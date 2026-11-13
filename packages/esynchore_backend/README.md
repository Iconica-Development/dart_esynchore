# esynchore_backend

Shelf adapters for accepting Esynchore commands over HTTP and streaming
principal-specific state over WebSockets.

Commands and state use separate endpoints. A successful command request
returns HTTP 204; authentication, authorization, and application failures are
returned as HTTP error responses to that command caller. The WebSocket
endpoint handles authentication, state updates, and heartbeats.

## Install

```sh
dart pub add esynchore_backend
```

## Configure routes

Create one `StateSessionService` for the server process, then mount both
handlers against it. Credentials for HTTP commands are read from the request;
WebSocket clients authenticate independently.

```dart
final sessions = StateSessionService<AppState, String, Principal>(
  authenticate: authenticate,
)..create("main", initialState);

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
  stateSerializer: viewSerializer,
  projectState: (state, principal) => projectFor(state, principal),
);
```

Mount `commands` at an HTTP `POST` route and `state` at a WebSocket route.
See [`example/main.dart`](example/main.dart) for a complete Shelf server.

## Behavior and lifecycle

The default command handler responds with 204 when a command is applied,
400 for an invalid payload, 401 for authentication failure, 403 for
authorization failure, and 409 for application failure. Error bodies use the
versioned Esynchore `ErrorMessage` format. Supply `failureResponse` or
`invalidRequestResponse` to customize responses.

The session service is in-memory and process-local. Route all requests for a
session to the process that owns it, and call `sessions.close()` during server
shutdown. Ensure `projectState` excludes any data the authenticated principal
must not see.

## Compatibility

Requires Dart 3.13 or later and Shelf.
