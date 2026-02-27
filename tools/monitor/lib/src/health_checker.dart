import 'dart:convert';

import 'package:http/http.dart' as http;

/// Health status of a server instance.
class HealthStatus {
  /// Creates a new [HealthStatus].
  const HealthStatus({
    required this.endpoint,
    required this.healthy,
    this.uptimeSeconds,
    this.version,
    required this.checkedAt,
    this.error,
  });

  /// The server endpoint that was checked.
  final String endpoint;

  /// Whether the server is healthy.
  final bool healthy;

  /// Server uptime in seconds, if available.
  final int? uptimeSeconds;

  /// Server version, if available.
  final String? version;

  /// When the health check was performed.
  final DateTime checkedAt;

  /// Error message if the server is unhealthy.
  final String? error;

  @override
  String toString() =>
      healthy
          ? '[$endpoint] OK (uptime: ${uptimeSeconds}s, v$version)'
          : '[$endpoint] UNHEALTHY: $error';
}

/// Periodically checks server health via the `/api/v1/health` endpoint.
class HealthChecker {
  /// Creates a new [HealthChecker] for the given [endpoint].
  HealthChecker({
    required this.endpoint,
    this.interval = const Duration(seconds: 30),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _history = [];

  /// The server endpoint to check.
  final String endpoint;

  /// The interval between health checks.
  final Duration interval;

  final http.Client _client;
  final List<HealthStatus> _history;
  bool _running = false;

  /// Performs a single health check.
  Future<HealthStatus> check() async {
    try {
      final response = await _client.get(Uri.parse('$endpoint/api/v1/health'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = HealthStatus(
          endpoint: endpoint,
          healthy: data['status'] == 'ok',
          uptimeSeconds: data['uptime'] as int?,
          version: data['version'] as String?,
          checkedAt: DateTime.now(),
        );
        _history.add(status);
        return status;
      }
      final status = HealthStatus(
        endpoint: endpoint,
        healthy: false,
        checkedAt: DateTime.now(),
        error: 'HTTP ${response.statusCode}',
      );
      _history.add(status);
      return status;
    } catch (e) {
      final status = HealthStatus(
        endpoint: endpoint,
        healthy: false,
        checkedAt: DateTime.now(),
        error: e.toString(),
      );
      _history.add(status);
      return status;
    }
  }

  /// Starts periodic health checking and yields each [HealthStatus].
  Stream<HealthStatus> monitor() async* {
    _running = true;
    while (_running) {
      yield await check();
      if (!_running) break;
      await Future<void>.delayed(interval);
    }
  }

  /// Stops the periodic monitoring loop.
  void stop() {
    _running = false;
  }

  /// Returns the history of all health checks performed.
  List<HealthStatus> get history => List.unmodifiable(_history);

  /// Returns the number of consecutive healthy checks from the end of history.
  int get consecutiveHealthy {
    var count = 0;
    for (var i = _history.length - 1; i >= 0; i--) {
      if (_history[i].healthy) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// Returns the uptime percentage based on the check history.
  ///
  /// Returns `100.0` if no checks have been performed.
  double get uptimePercentage {
    if (_history.isEmpty) return 100.0;
    final healthyCount = _history.where((s) => s.healthy).length;
    return (healthyCount / _history.length) * 100.0;
  }

  /// Closes the underlying HTTP client.
  void close() {
    _client.close();
  }
}
