import "package:counter_domain/counter_domain.dart";
import "package:esynchore_backend/esynchore_backend.dart";

final sessions = StateSessionService<Counters, String, int>(authenticate: authenticate)
  ..create("counter", const Counters());
