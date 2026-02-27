import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lattice_monitor/lattice_monitor.dart';
import 'package:test/test.dart';

/// A mock HTTP client that delegates to a handler function.
class MockHttpClient extends http.BaseClient {
  MockHttpClient(this.handler);

  http.Response Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  group('HealthStatus', () {
    test('toString for healthy status', () {
      final status = HealthStatus(
        endpoint: 'http://localhost:8080',
        healthy: true,
        uptimeSeconds: 3600,
        version: '1.0.0',
        checkedAt: DateTime.now(),
      );
      expect(
        status.toString(),
        equals('[http://localhost:8080] OK (uptime: 3600s, v1.0.0)'),
      );
    });

    test('toString for unhealthy status', () {
      final status = HealthStatus(
        endpoint: 'http://localhost:8080',
        healthy: false,
        checkedAt: DateTime.now(),
        error: 'Connection refused',
      );
      expect(
        status.toString(),
        equals('[http://localhost:8080] UNHEALTHY: Connection refused'),
      );
    });

    test('construction with all fields', () {
      final now = DateTime.now();
      final status = HealthStatus(
        endpoint: 'http://example.com',
        healthy: true,
        uptimeSeconds: 120,
        version: '2.0.0',
        checkedAt: now,
        error: null,
      );
      expect(status.endpoint, equals('http://example.com'));
      expect(status.healthy, isTrue);
      expect(status.uptimeSeconds, equals(120));
      expect(status.version, equals('2.0.0'));
      expect(status.checkedAt, equals(now));
      expect(status.error, isNull);
    });
  });

  group('HealthChecker', () {
    test('check returns healthy status for valid response', () async {
      final client = MockHttpClient((request) {
        expect(request.url.path, equals('/api/v1/health'));
        return http.Response(
          jsonEncode({'status': 'ok', 'uptime': 3600, 'version': '1.0.0'}),
          200,
        );
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      final status = await checker.check();
      expect(status.healthy, isTrue);
      expect(status.uptimeSeconds, equals(3600));
      expect(status.version, equals('1.0.0'));
      checker.close();
    });

    test('check returns unhealthy status for non-200 response', () async {
      final client = MockHttpClient(
        (_) => http.Response('Internal Server Error', 500),
      );

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      final status = await checker.check();
      expect(status.healthy, isFalse);
      expect(status.error, equals('HTTP 500'));
      checker.close();
    });

    test('check returns unhealthy status on connection error', () async {
      final client = MockHttpClient((_) {
        throw Exception('Connection refused');
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      final status = await checker.check();
      expect(status.healthy, isFalse);
      expect(status.error, contains('Connection refused'));
      checker.close();
    });

    test('history tracks all checks', () async {
      var callCount = 0;
      final client = MockHttpClient((_) {
        callCount++;
        if (callCount <= 2) {
          return http.Response(
            jsonEncode({'status': 'ok', 'uptime': 100, 'version': '1.0.0'}),
            200,
          );
        }
        return http.Response('error', 500);
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      await checker.check();
      await checker.check();
      await checker.check();

      expect(checker.history, hasLength(3));
      expect(checker.history[0].healthy, isTrue);
      expect(checker.history[1].healthy, isTrue);
      expect(checker.history[2].healthy, isFalse);
      checker.close();
    });

    test('consecutiveHealthy counts from end of history', () async {
      final responses = [true, false, true, true, true];
      var index = 0;
      final client = MockHttpClient((_) {
        final healthy = responses[index++];
        if (healthy) {
          return http.Response(
            jsonEncode({'status': 'ok', 'uptime': 100, 'version': '1.0.0'}),
            200,
          );
        }
        return http.Response('error', 500);
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      for (var i = 0; i < responses.length; i++) {
        await checker.check();
      }

      expect(checker.consecutiveHealthy, equals(3));
      checker.close();
    });

    test('consecutiveHealthy is 0 when last check failed', () async {
      final client = MockHttpClient((_) => http.Response('error', 500));

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      await checker.check();
      expect(checker.consecutiveHealthy, equals(0));
      checker.close();
    });

    test('uptimePercentage calculates correctly', () async {
      var callCount = 0;
      final client = MockHttpClient((_) {
        callCount++;
        if (callCount <= 3) {
          return http.Response(
            jsonEncode({'status': 'ok', 'uptime': 100, 'version': '1.0.0'}),
            200,
          );
        }
        return http.Response('error', 500);
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      await checker.check(); // healthy
      await checker.check(); // healthy
      await checker.check(); // healthy
      await checker.check(); // unhealthy

      expect(checker.uptimePercentage, equals(75.0));
      checker.close();
    });

    test('uptimePercentage is 100 when no checks', () {
      final checker = HealthChecker(endpoint: 'http://localhost:8080');
      expect(checker.uptimePercentage, equals(100.0));
      checker.close();
    });

    test('monitor yields statuses and can be stopped', () async {
      var callCount = 0;
      final client = MockHttpClient((_) {
        callCount++;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'uptime': callCount * 10,
            'version': '1.0.0',
          }),
          200,
        );
      });

      final checker = HealthChecker(
        endpoint: 'http://localhost:8080',
        interval: const Duration(milliseconds: 10),
        client: client,
      );

      final statuses = <HealthStatus>[];
      await for (final status in checker.monitor()) {
        statuses.add(status);
        if (statuses.length >= 3) {
          checker.stop();
        }
      }

      expect(statuses, hasLength(3));
      expect(statuses.every((s) => s.healthy), isTrue);
      checker.close();
    });
  });

  group('MetricsSnapshot', () {
    test('construction with all fields', () {
      final now = DateTime.now();
      final snapshot = MetricsSnapshot(
        endpoint: 'http://localhost:8080',
        userCount: 10,
        preKeyCount: 500,
        pendingMessageCount: 25,
        uptimeSeconds: 7200,
        collectedAt: now,
      );
      expect(snapshot.endpoint, equals('http://localhost:8080'));
      expect(snapshot.userCount, equals(10));
      expect(snapshot.preKeyCount, equals(500));
      expect(snapshot.pendingMessageCount, equals(25));
      expect(snapshot.uptimeSeconds, equals(7200));
      expect(snapshot.collectedAt, equals(now));
    });

    test('toString formats correctly', () {
      final snapshot = MetricsSnapshot(
        endpoint: 'http://localhost:8080',
        userCount: 10,
        preKeyCount: 500,
        pendingMessageCount: 25,
        uptimeSeconds: 7200,
        collectedAt: DateTime.now(),
      );
      expect(
        snapshot.toString(),
        equals('Users: 10, PreKeys: 500, Messages: 25, Uptime: 7200s'),
      );
    });
  });

  group('MetricsCollector', () {
    test('collect returns snapshot for valid response', () async {
      final client = MockHttpClient((request) {
        expect(request.url.path, equals('/api/v1/metrics'));
        return http.Response(
          jsonEncode({
            'users': 42,
            'preKeys': 1000,
            'pendingMessages': 5,
            'uptime': 3600,
          }),
          200,
        );
      });

      final collector = MetricsCollector(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      final snapshot = await collector.collect();
      expect(snapshot.userCount, equals(42));
      expect(snapshot.preKeyCount, equals(1000));
      expect(snapshot.pendingMessageCount, equals(5));
      expect(snapshot.uptimeSeconds, equals(3600));
      collector.close();
    });

    test('collect throws on non-200 response', () async {
      final client = MockHttpClient((_) => http.Response('error', 500));

      final collector = MetricsCollector(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      await expectLater(collector.collect, throwsException);
      collector.close();
    });

    test('history tracks all collections', () async {
      var callCount = 0;
      final client = MockHttpClient((_) {
        callCount++;
        return http.Response(
          jsonEncode({
            'users': callCount,
            'preKeys': 100,
            'pendingMessages': 0,
            'uptime': callCount * 60,
          }),
          200,
        );
      });

      final collector = MetricsCollector(
        endpoint: 'http://localhost:8080',
        client: client,
      );

      await collector.collect();
      await collector.collect();

      expect(collector.history, hasLength(2));
      expect(collector.history[0].userCount, equals(1));
      expect(collector.history[1].userCount, equals(2));
      collector.close();
    });

    test('monitor yields snapshots and can be stopped', () async {
      var callCount = 0;
      final client = MockHttpClient((_) {
        callCount++;
        return http.Response(
          jsonEncode({
            'users': callCount,
            'preKeys': 100,
            'pendingMessages': 0,
            'uptime': callCount * 60,
          }),
          200,
        );
      });

      final collector = MetricsCollector(
        endpoint: 'http://localhost:8080',
        interval: const Duration(milliseconds: 10),
        client: client,
      );

      final snapshots = <MetricsSnapshot>[];
      await for (final snapshot in collector.monitor()) {
        snapshots.add(snapshot);
        if (snapshots.length >= 2) {
          collector.stop();
        }
      }

      expect(snapshots, hasLength(2));
      collector.close();
    });
  });

  group('Alert', () {
    test('construction with all fields', () {
      final now = DateTime.now();
      final alert = Alert(
        severity: AlertSeverity.critical,
        message: 'Server down',
        triggeredAt: now,
      );
      expect(alert.severity, equals(AlertSeverity.critical));
      expect(alert.message, equals('Server down'));
      expect(alert.triggeredAt, equals(now));
    });

    test('toString formats with severity', () {
      final alert = Alert(
        severity: AlertSeverity.warning,
        message: 'High load',
        triggeredAt: DateTime.now(),
      );
      expect(alert.toString(), equals('[WARNING] High load'));
    });

    test('toString formats info severity', () {
      final alert = Alert(
        severity: AlertSeverity.info,
        message: 'Server started',
        triggeredAt: DateTime.now(),
      );
      expect(alert.toString(), equals('[INFO] Server started'));
    });

    test('toString formats critical severity', () {
      final alert = Alert(
        severity: AlertSeverity.critical,
        message: 'Server unreachable',
        triggeredAt: DateTime.now(),
      );
      expect(alert.toString(), equals('[CRITICAL] Server unreachable'));
    });
  });

  group('AlertThreshold', () {
    test('default values', () {
      const threshold = AlertThreshold();
      expect(threshold.maxConsecutiveFailures, equals(3));
      expect(threshold.maxPendingMessages, equals(1000));
      expect(threshold.minUptimePercentage, equals(99.0));
    });

    test('custom values', () {
      const threshold = AlertThreshold(
        maxConsecutiveFailures: 5,
        maxPendingMessages: 500,
        minUptimePercentage: 95.0,
      );
      expect(threshold.maxConsecutiveFailures, equals(5));
      expect(threshold.maxPendingMessages, equals(500));
      expect(threshold.minUptimePercentage, equals(95.0));
    });

    test('nullable values', () {
      const threshold = AlertThreshold(
        maxConsecutiveFailures: null,
        maxPendingMessages: null,
        minUptimePercentage: null,
      );
      expect(threshold.maxConsecutiveFailures, isNull);
      expect(threshold.maxPendingMessages, isNull);
      expect(threshold.minUptimePercentage, isNull);
    });
  });

  group('AlertManager', () {
    test('evaluateHealth triggers warning for single failure', () {
      final manager = AlertManager();
      final status = HealthStatus(
        endpoint: 'http://localhost:8080',
        healthy: false,
        checkedAt: DateTime.now(),
        error: 'Connection refused',
      );

      manager.evaluateHealth(status, consecutiveFailures: 1);

      expect(manager.alerts, hasLength(1));
      expect(manager.alerts[0].severity, equals(AlertSeverity.warning));
      expect(manager.alerts[0].message, contains('health check failed'));
    });

    test('evaluateHealth triggers critical for consecutive failures', () {
      final manager = AlertManager(
        threshold: const AlertThreshold(maxConsecutiveFailures: 3),
      );
      final status = HealthStatus(
        endpoint: 'http://localhost:8080',
        healthy: false,
        checkedAt: DateTime.now(),
        error: 'Connection refused',
      );

      manager.evaluateHealth(status, consecutiveFailures: 3);

      expect(manager.alerts, hasLength(1));
      expect(manager.alerts[0].severity, equals(AlertSeverity.critical));
      expect(manager.alerts[0].message, contains('3 consecutive failures'));
    });

    test('evaluateHealth does not alert for healthy status', () {
      final manager = AlertManager();
      final status = HealthStatus(
        endpoint: 'http://localhost:8080',
        healthy: true,
        uptimeSeconds: 3600,
        version: '1.0.0',
        checkedAt: DateTime.now(),
      );

      manager.evaluateHealth(status);

      expect(manager.alerts, isEmpty);
    });

    test('evaluateMetrics triggers warning for pending message threshold', () {
      final manager = AlertManager(
        threshold: const AlertThreshold(maxPendingMessages: 100),
      );
      final snapshot = MetricsSnapshot(
        endpoint: 'http://localhost:8080',
        userCount: 10,
        preKeyCount: 500,
        pendingMessageCount: 150,
        uptimeSeconds: 3600,
        collectedAt: DateTime.now(),
      );

      manager.evaluateMetrics(snapshot);

      expect(manager.alerts, hasLength(1));
      expect(manager.alerts[0].severity, equals(AlertSeverity.warning));
      expect(manager.alerts[0].message, contains('150 pending messages'));
    });

    test('evaluateMetrics does not alert below threshold', () {
      final manager = AlertManager(
        threshold: const AlertThreshold(maxPendingMessages: 100),
      );
      final snapshot = MetricsSnapshot(
        endpoint: 'http://localhost:8080',
        userCount: 10,
        preKeyCount: 500,
        pendingMessageCount: 50,
        uptimeSeconds: 3600,
        collectedAt: DateTime.now(),
      );

      manager.evaluateMetrics(snapshot);

      expect(manager.alerts, isEmpty);
    });

    test('evaluateMetrics does not alert when threshold is null', () {
      final manager = AlertManager(
        threshold: const AlertThreshold(maxPendingMessages: null),
      );
      final snapshot = MetricsSnapshot(
        endpoint: 'http://localhost:8080',
        userCount: 10,
        preKeyCount: 500,
        pendingMessageCount: 99999,
        uptimeSeconds: 3600,
        collectedAt: DateTime.now(),
      );

      manager.evaluateMetrics(snapshot);

      expect(manager.alerts, isEmpty);
    });

    test('evaluateUptime triggers critical below threshold', () {
      final manager = AlertManager(
        threshold: const AlertThreshold(minUptimePercentage: 99.0),
      );

      manager.evaluateUptime(95.5);

      expect(manager.alerts, hasLength(1));
      expect(manager.alerts[0].severity, equals(AlertSeverity.critical));
      expect(manager.alerts[0].message, contains('95.5%'));
    });

    test('evaluateUptime does not alert above threshold', () {
      final manager = AlertManager(
        threshold: const AlertThreshold(minUptimePercentage: 99.0),
      );

      manager.evaluateUptime(99.5);

      expect(manager.alerts, isEmpty);
    });

    test('evaluateUptime does not alert when threshold is null', () {
      final manager = AlertManager(
        threshold: const AlertThreshold(minUptimePercentage: null),
      );

      manager.evaluateUptime(50.0);

      expect(manager.alerts, isEmpty);
    });

    test('onAlert callback is invoked', () {
      final receivedAlerts = <Alert>[];
      final manager = AlertManager(onAlert: receivedAlerts.add);

      final status = HealthStatus(
        endpoint: 'http://localhost:8080',
        healthy: false,
        checkedAt: DateTime.now(),
        error: 'timeout',
      );

      manager.evaluateHealth(status, consecutiveFailures: 1);

      expect(receivedAlerts, hasLength(1));
      expect(receivedAlerts[0].severity, equals(AlertSeverity.warning));
    });

    test('clearAlerts removes all alerts', () {
      final manager = AlertManager();
      final status = HealthStatus(
        endpoint: 'http://localhost:8080',
        healthy: false,
        checkedAt: DateTime.now(),
        error: 'error',
      );

      manager.evaluateHealth(status, consecutiveFailures: 1);
      expect(manager.alerts, hasLength(1));

      manager.clearAlerts();
      expect(manager.alerts, isEmpty);
    });

    test('multiple evaluations accumulate alerts', () {
      final manager = AlertManager(
        threshold: const AlertThreshold(
          maxPendingMessages: 100,
          minUptimePercentage: 99.0,
        ),
      );

      final status = HealthStatus(
        endpoint: 'http://localhost:8080',
        healthy: false,
        checkedAt: DateTime.now(),
        error: 'error',
      );
      manager.evaluateHealth(status, consecutiveFailures: 1);

      final snapshot = MetricsSnapshot(
        endpoint: 'http://localhost:8080',
        userCount: 10,
        preKeyCount: 500,
        pendingMessageCount: 200,
        uptimeSeconds: 3600,
        collectedAt: DateTime.now(),
      );
      manager.evaluateMetrics(snapshot);

      manager.evaluateUptime(95.0);

      expect(manager.alerts, hasLength(3));
    });
  });
}
