# esynchore_flutter

HTTP command client for Esynchore. It sends commands and returns the command
endpoint's result directly to the caller, independently of any WebSocket used
to stream state.

Although this package is Flutter-friendly, it does not contain Flutter widgets.
It can also be used from Dart applications.

## Install

```sh
flutter pub add esynchore_flutter
```

## Submit a command

Provide a serializer for the command and a callback that converts credentials
into the headers expected by your server:

```dart
final commands = HttpCommandClient<String, AppCommand>(
  endpoint: Uri.parse("https://example.com/commands"),
  commandSerializer: commandSerializer,
  headersForCredentials: (token) => {"authorization": token},
);

final result = await commands.submit(command, accessToken);
result.match(
  (error) => showError(error.message),
  (_) => showSuccess(),
);

commands.close();
```

`submit` returns expected server errors as `ErrorMessage` values. Use
`submitWithResponse` when the caller also needs the original HTTP response,
including its status and headers. Network, credential-provider, and encoding
exceptions are propagated.

## Resource ownership

The client owns and closes the HTTP client it creates. If you inject an
`http.Client`, that client remains owned by your application and is not closed
by `HttpCommandClient.close()`.

See [`example/main.dart`](example/main.dart) for a minimal command client.

## Compatibility

Requires Dart 3.13 or later.
