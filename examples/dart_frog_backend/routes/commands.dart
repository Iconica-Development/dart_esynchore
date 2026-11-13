import "package:counter_dart_frog_backend/sessions.dart";
import "package:counter_domain/counter_domain.dart";
import "package:dart_frog/dart_frog.dart";
import "package:esynchore_dart_frog/esynchore_dart_frog.dart";

Future<Response> onRequest(RequestContext context) => SessionCommandView(
  sessions: sessions,
  id: "counter",
  commandSerializer: commandSerializer,
  readCredentials: (context) => context.request.headers["authorization"] ?? "",
).asView(context);
