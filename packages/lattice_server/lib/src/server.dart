import 'dart:io';

import 'package:shelf/shelf.dart' hide Middleware;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'middleware.dart';
import 'routes.dart';
import 'storage.dart';

/// The Lattice key distribution server.
///
/// Wraps a Shelf HTTP server with the appropriate middleware pipeline and
/// API routes for the post-quantum Signal protocol.
class LatticeServer {
  /// Creates a [LatticeServer].
  ///
  /// If [storage] is not provided, an [InMemoryStorage] instance is used.
  LatticeServer({Storage? storage, this.host = 'localhost', this.port = 8080})
    : storage = storage ?? InMemoryStorage();

  /// The storage backend.
  final Storage storage;

  /// The host address to bind to.
  final String host;

  /// The port to listen on.
  final int port;

  HttpServer? _server;

  /// Starts the server and begins listening for requests.
  Future<void> start() async {
    final routes = Routes(storage);
    final handler = const Pipeline()
        .addMiddleware(Middleware.errorHandler())
        .addMiddleware(Middleware.logging())
        .addMiddleware(Middleware.cors())
        .addHandler(routes.router.call);

    _server = await shelf_io.serve(handler, host, port);

    // ignore: avoid_print
    print('Lattice server listening on $host:$port');
  }

  /// Stops the server gracefully.
  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  /// Whether the server is currently running.
  bool get isRunning => _server != null;
}
