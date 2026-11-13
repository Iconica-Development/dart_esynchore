import "dart:io";

import "package:counter_domain/counter_domain.dart";
import "package:esynchore_backend/esynchore_backend.dart";
import "package:shelf/shelf.dart";
import "package:shelf/shelf_io.dart" as shelf_io;

Future<void> main(List<String> args) async {
  final sessions = StateSessionService<Counters, String, int>(authenticate: authenticate,)
    ..create("counter", const Counters());

  final commands = sessionCommandHandler(
    sessions: sessions,
    id: "counter",
    commandSerializer: commandSerializer,
    readCredentials: (request) => request.headers["authorization"] ?? "",
  );

  final state = sessionWebSocketHandler(
    sessions: sessions,
    id: "counter",
    credentialsSerializer: credentialsSerializer,
    stateSerializer: countersSerializer,
    projectState: (state, principal) => state,
  );

  final server = await shelf_io.serve(
    const Pipeline().addMiddleware(_cors()).addHandler(
      (request) => switch (request.url.path) {
        "commands" => commands(request),
        "state" => state(request),
        _ => Response.notFound("Not found"),
      },
    ),
    InternetAddress.anyIPv4,
    args.isEmpty ? 8080 : int.parse(args.first),
  );
  
  stdout.writeln("Listening on http://localhost:${server.port}");
}

Middleware _cors() {
  const headers = {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
  };
  return (handler) => (request) async {
    if (request.method == "OPTIONS") {
      return Response(204, headers: headers);
    }
    final response = await handler(request);
    return response.change(headers: headers);
  };
}
