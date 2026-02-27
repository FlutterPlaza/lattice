import 'dart:convert';

import 'package:http/http.dart' as http;

/// A snapshot of server metrics at a point in time.
class MetricsSnapshot {
  /// Creates a new [MetricsSnapshot].
  const MetricsSnapshot({
    required this.endpoint,
    required this.userCount,
    required this.preKeyCount,
    required this.pendingMessageCount,
    required this.uptimeSeconds,
    required this.collectedAt,
  });

  /// The server endpoint the metrics were collected from.
  final String endpoint;

  /// Number of registered users.
  final int userCount;

  /// Number of available pre-keys.
  final int preKeyCount;

  /// Number of pending (undelivered) messages.
  final int pendingMessageCount;

  /// Server uptime in seconds.
  final int uptimeSeconds;

  /// When the metrics were collected.
  final DateTime collectedAt;

  @override
  String toString() =>
      'Users: $userCount, PreKeys: $preKeyCount, '
      'Messages: $pendingMessageCount, Uptime: ${uptimeSeconds}s';
}

/// Collects server metrics periodically via the `/api/v1/metrics` endpoint.
class MetricsCollector {
  /// Creates a new [MetricsCollector] for the given [endpoint].
  MetricsCollector({
    required this.endpoint,
    this.interval = const Duration(seconds: 60),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _history = [];

  /// The server endpoint to collect metrics from.
  final String endpoint;

  /// The interval between metric collections.
  final Duration interval;

  final http.Client _client;
  final List<MetricsSnapshot> _history;
  bool _running = false;

  /// Collects metrics once from the server.
  Future<MetricsSnapshot> collect() async {
    final response = await _client.get(Uri.parse('$endpoint/api/v1/metrics'));
    if (response.statusCode != 200) {
      throw Exception(
        'Metrics request failed with status ${response.statusCode}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final snapshot = MetricsSnapshot(
      endpoint: endpoint,
      userCount: data['users'] as int? ?? 0,
      preKeyCount: data['preKeys'] as int? ?? 0,
      pendingMessageCount: data['pendingMessages'] as int? ?? 0,
      uptimeSeconds: data['uptime'] as int? ?? 0,
      collectedAt: DateTime.now(),
    );
    _history.add(snapshot);
    return snapshot;
  }

  /// Starts periodic metric collection and yields each [MetricsSnapshot].
  Stream<MetricsSnapshot> monitor() async* {
    _running = true;
    while (_running) {
      yield await collect();
      if (!_running) break;
      await Future<void>.delayed(interval);
    }
  }

  /// Stops the periodic collection loop.
  void stop() {
    _running = false;
  }

  /// Returns the history of all metric snapshots collected.
  List<MetricsSnapshot> get history => List.unmodifiable(_history);

  /// Closes the underlying HTTP client.
  void close() {
    _client.close();
  }
}
