import "package:esynchore_core/src/models/esynchore_error.dart";
import "package:fpdart/fpdart.dart";
import "package:meta/meta.dart";

/// A requested transition of [StateType] issued by a [Principal].
///
/// Implementations must not mutate the state passed to either method. The
/// handler calls [authorize] and, only if it succeeds, [apply] against the
/// same current state. Both methods must be synchronous and should return
/// expected failures rather than throwing them.
abstract class StateCommand<StateType, Principal> {
  /// Creates a command.
  const StateCommand();

  /// A stable discriminator for the application's command codec.
  String get type;

  /// Checks whether [principal] may execute this command against [state].
  @useResult
  TaskEither<AuthorizationError, Unit> authorize(StateType state, Principal principal);

  /// Returns a new state, or an error if the transition is not valid.
  @useResult
  TaskEither<ApplicationError, StateType> apply(StateType state, Principal principal);
}

/// An application-provided resource identifier.
extension type ResourceId(String id) {}
