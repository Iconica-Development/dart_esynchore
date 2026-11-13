# esynchore_dart_frog

Dart Frog route adapters for Esynchore sessions. Use
`SessionWebSocketView` to publish a principal-specific state stream and
`SessionCommandView` to receive commands over HTTP.

Command results are returned through the HTTP request that submitted them.
The WebSocket route is reserved for authentication, state updates, and
heartbeats.

## Install

```sh
dart pub add esynchore_dart_frog
```

## Add routes

Create a single `StateSessionService` for the server process (for example in a
shared `lib/` file), then bind route IDs to its handlers:

```dart
Future<Response> onRequest(RequestContext context) =>
    SessionWebSocketView(
      sessions: sessions,
      id: "main",
      credentialsSerializer: credentialsSerializer,
      stateSerializer: stateSerializer,
      projectState: (state, principal) => projectFor(state, principal),
    ).asView(context);
```

For commands, use `SessionCommandView` with the same service and ID, a command
serializer, and a `readCredentials` callback that reads credentials from the
request. See [`example/main.dart`](example/main.dart) for both view
configurations.

## Session lifecycle

Keep the session service alive for the lifetime of the server and close it
during application shutdown. The service is in-memory and process-local; route
each session's requests to the process that owns it. Filter state in
`projectState` so the WebSocket sends only data the principal may see.

## Compatibility

Requires Dart 3.13 or later and Dart Frog.
