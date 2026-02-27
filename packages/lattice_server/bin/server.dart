import 'dart:io';

import 'package:args/args.dart';
import 'package:lattice_server/lattice_server.dart';

/// CLI entry point for the Lattice key distribution server.
void main(List<String> arguments) async {
  final parser =
      ArgParser()
        ..addOption(
          'port',
          abbr: 'p',
          defaultsTo: '8080',
          help: 'Port to listen on',
        )
        ..addOption(
          'host',
          abbr: 'H',
          defaultsTo: 'localhost',
          help: 'Host address to bind to',
        )
        ..addOption(
          'storage-path',
          help: 'Path for file-based persistent storage (omit for in-memory)',
        )
        ..addFlag('help', negatable: false, help: 'Show usage information');

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (results.flag('help')) {
    stdout.writeln('Lattice Signal Server');
    stdout.writeln('');
    stdout.writeln(
      'A post-quantum key distribution server for the Lattice protocol.',
    );
    stdout.writeln('');
    stdout.writeln('Usage: dart run lattice_server [options]');
    stdout.writeln('');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final storagePath = results.option('storage-path');
  final Storage storage =
      storagePath != null ? FileStorage(storagePath) : InMemoryStorage();

  final portString = results.option('port') ?? '8080';
  final port = int.tryParse(portString);
  if (port == null) {
    stderr.writeln('Error: Invalid port number "$portString"');
    exit(1);
  }

  final server = LatticeServer(
    storage: storage,
    host: results.option('host') ?? 'localhost',
    port: port,
  );

  await server.start();

  // Handle SIGINT (Ctrl-C) for graceful shutdown.
  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nShutting down...');
    await server.stop();
    exit(0);
  });
}
