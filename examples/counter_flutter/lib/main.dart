import "dart:async";

import "package:counter_domain/counter_domain.dart";
import "package:esynchore_core/esynchore_core.dart";
import "package:esynchore_flutter/esynchore_flutter.dart";
import "package:flutter/material.dart";
import "package:web_socket_channel/web_socket_channel.dart";

void main() => runApp(const CounterApp());

class CounterApp extends StatelessWidget {
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Shared counters",
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const CounterPage(),
  );
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  final url = TextEditingController(text: "ws://localhost:8080/state");
  final commandUrl = TextEditingController(
    text: "http://localhost:8080/commands",
  );
  final credentials = TextEditingController(text: "auth:1");
  HttpCommandClient<String, StateCommand<Counters, int>>? commandClient;
  WebSocketProtocolConnection? connection;
  Counters? counters;
  String status = "Disconnected";
  bool connecting = false;

  Future<void> connect() async {
    final previous = connection;
    final previousCommandClient = commandClient;
    connection = null;
    commandClient = null;
    
    setState(() {
      connecting = true;
      counters = null;
      status = "Connecting";
    });

    await previous?.close();
    previousCommandClient?.close();
    if (!mounted) return;
    final nextClient = ProtocolClient<String, Counters>(
      credentialsSerializer: credentialsSerializer,
      stateSerializer: countersSerializer,
    );

    HttpCommandClient<String, StateCommand<Counters, int>>? nextCommandClient;
    try {
      nextCommandClient = HttpCommandClient<String, StateCommand<Counters, int>>(
        endpoint: Uri.parse(commandUrl.text),
        commandSerializer: commandSerializer,
        headersForCredentials: (credentials) => {
          "authorization": credentials,
        },
      );

      commandClient = nextCommandClient;
      final channel = WebSocketChannel.connect(Uri.parse(url.text));
      final nextConnection = WebSocketProtocolConnection.client(channel, nextClient);
      connection = nextConnection;
      nextClient.stateChanges.listen((state) {
        if (mounted) setState(() => counters = state);
      });

      nextClient.errors.listen((error) {
        if (mounted) setState(() => status = error.message);
      });

      unawaited(
        nextConnection.done.then((_) {
          if (mounted && identical(connection, nextConnection)) {
            setState(() {
              counters = null;
              status = "Disconnected";
            });
          }
        }),
      );
      await channel.ready;
      final result = await nextClient.authenticate(credentials.text);
      if (!mounted) return;
      result.match((error) {
        connection = null;
        commandClient = null;
        nextCommandClient?.close();
        setState(() => status = error.message);
        unawaited(nextConnection.close());
      }, (_) => setState(() => status = "Connected"));
    } on Object catch (error) {
      final failed = connection;
      connection = null;
      commandClient = null;
      nextCommandClient?.close();
      if (failed == null) {
        await nextClient.close();
      } else {
        await failed.close();
      }
      if (mounted) setState(() => status = error.toString());
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> increment(int counter) async {
    final active = commandClient;
    if (active == null) return;
    final result = await active.submit(Increment(counter), credentials.text);
    if (!mounted) return;
    result.match((error) => setState(() => status = error.message), (_) {});
  }

  @override
  void dispose() {
    unawaited(connection?.close());
    commandClient?.close();
    url.dispose();
    commandUrl.dispose();
    credentials.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Shared counters")),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: url,
              decoration: const InputDecoration(labelText: "WebSocket URL"),
            ),
            TextField(
              controller: commandUrl,
              decoration: const InputDecoration(labelText: "HTTP command URL"),
            ),
            TextField(
              controller: credentials,
              decoration: const InputDecoration(labelText: "Credentials"),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: connecting ? null : connect, child: const Text("Connect")),
            const SizedBox(height: 16),
            Text(status),
            const SizedBox(height: 24),
            for (final (number, value) in [(1, counters?.first), (2, counters?.second)]) ...[
              ListTile(
                title: Text("Counter $number"),
                subtitle: Text(value?.toString() ?? "-"),
                trailing: IconButton(
                  tooltip: "Increment counter $number",
                  onPressed: value == null ? null : () => increment(number),
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
