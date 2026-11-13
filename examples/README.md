# Counter examples

From the workspace root, run `flutter pub get`, then start one backend:

```sh
dart run examples/shelf_backend/bin/server.dart
cd examples/dart_frog_backend && dart_frog dev
```

In separate terminals:

```sh
dart run examples/counter_cli/bin/counter.dart watch ws://localhost:8080/state auth:1
dart run examples/counter_cli/bin/counter.dart send http://localhost:8080/commands auth:2 2
cd examples/counter_flutter && flutter run -d chrome
```

Use `auth:1` or `auth:2`. Both can watch both counters, but each can increment only its own. Both backends keep their state in memory.