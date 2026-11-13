// ignore_for_file: avoid_print

import "package:dart_iconica_utilities/dart_iconica_utilities.dart";
import "package:esynchore_flutter/esynchore_flutter.dart";

Future<void> main() async {
  final commands = HttpCommandClient<String, int>(
    endpoint: Uri.parse("http://localhost:8080/commands"),
    commandSerializer: Serializer<int>(
      fromMap: (map) => map["amount"] is int
          ? map["amount"] as int
          : throw const FormatException("Expected an integer amount."),
      toMap: (amount) => {"amount": amount},
    ),
    headersForCredentials: (token) => {"authorization": token},
  );

  final result = await commands.submit(1, "demo");
  result.match(
    (error) => print("${error.code}: ${error.message}"),
    (_) => print("Command accepted."),
  );
  commands.close();
}
