import "dart:io";

import "package:counter_domain/counter_domain.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:esynchore_flutter/esynchore_flutter.dart";
import "package:web_socket_channel/web_socket_channel.dart";

Future<void> main(List<String> args) async {
  if (args.length == 3 && args[0] == "watch") {
    final client = ProtocolClient(
      credentialsSerializer: credentialsSerializer,
      stateSerializer: countersSerializer,
    );

    final channel = WebSocketChannel.connect(Uri.parse(args[1]));
    final connection = WebSocketProtocolConnection.client(channel, client);
    client.stateChanges.listen((state) => stdout.writeln("1: ${state.first}  2: ${state.second}"));
    client.errors.listen((error) => stderr.writeln(error.message));

    try {
      await channel.ready;
      final result = await client.authenticate(args[2]);
      if (result.isLeft()) {
        result.match((error) => stderr.writeln(error.message), (_) {});
        exitCode = 1;
        await connection.close();
      } else {
        await connection.done;
      }
    } on Object catch (error) {
      stderr.writeln(error);
      exitCode = 1;
      await connection.close();
    }
  } else if (args.length == 4 && args[0] == "send" && (args[3] == "1" || args[3] == "2")) {
    final client = HttpCommandClient<String, StateCommand<Counters, int>>(
      endpoint: Uri.parse(args[1]),
      commandSerializer: commandSerializer,
      headersForCredentials: (credentials) => {"authorization": credentials},
    );
    try {
      final result = await client.submit(Increment(int.parse(args[3])), args[2]);
      result.match((error) {
        stderr.writeln(error.message);
        exitCode = 1;
      }, (_) => stdout.writeln("Accepted"));
    } on Object catch (error) {
      stderr.writeln(error);
      exitCode = 1;
    } finally {
      client.close();
    }
  } else {
    stderr.writeln(
      "Usage: counter watch <ws-url> <auth:1|auth:2>\n"
      "       counter send <http-url> <auth:1|auth:2> <1|2>",
    );
    exitCode = 64;
  }
}
