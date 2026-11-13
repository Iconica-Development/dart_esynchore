import "package:counter_dart_frog_backend/sessions.dart";
import "package:counter_domain/counter_domain.dart";
import "package:dart_frog/dart_frog.dart";
import "package:esynchore_dart_frog/esynchore_dart_frog.dart";

Future<Response> onRequest(RequestContext context) => SessionWebSocketView(
  sessions: sessions,
  id: "counter",
  credentialsSerializer: credentialsSerializer,
  stateSerializer: countersSerializer,
  projectState: (state, principal) => state,
).asView(context);
