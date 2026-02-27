import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:lattice_monitor/lattice_monitor.dart';

void main(List<String> args) async {
  final parser =
      ArgParser()
        ..addOption(
          'endpoint',
          abbr: 'e',
          defaultsTo: 'http://localhost:8080',
          help: 'Server endpoint URL',
        )
        ..addOption(
          'interval',
          abbr: 'i',
          defaultsTo: '30',
          help: 'Check interval in seconds',
        )
        ..addOption(
          'max-failures',
          defaultsTo: '3',
          help: 'Max consecutive failures before critical alert',
        )
        ..addFlag(
          'metrics',
          defaultsTo: true,
          help: 'Also collect metrics periodically',
        )
        ..addFlag('help', negatable: false, help: 'Show usage information');

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Usage: dart run lattice_monitor [options]');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (results.flag('help')) {
    stdout.writeln('Lattice Signal Server Monitor');
    stdout.writeln('');
    stdout.writeln('Usage: dart run lattice_monitor [options]');
    stdout.writeln('');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final endpoint = results.option('endpoint')!;
  final intervalSeconds = int.tryParse(results.option('interval')!) ?? 30;
  final maxFailures = int.tryParse(results.option('max-failures')!) ?? 3;
  final collectMetrics = results.flag('metrics');

  final healthChecker = HealthChecker(
    endpoint: endpoint,
    interval: Duration(seconds: intervalSeconds),
  );

  final alertManager = AlertManager(
    threshold: AlertThreshold(maxConsecutiveFailures: maxFailures),
    onAlert: (alert) {
      stderr.writeln(alert);
    },
  );

  stdout.writeln('Monitoring $endpoint every ${intervalSeconds}s...');
  stdout.writeln('Press Ctrl+C to stop.');
  stdout.writeln('');

  MetricsCollector? metricsCollector;
  StreamSubscription<MetricsSnapshot>? metricsSub;

  if (collectMetrics) {
    metricsCollector = MetricsCollector(
      endpoint: endpoint,
      interval: Duration(seconds: intervalSeconds * 2),
    );
    metricsSub = metricsCollector.monitor().listen(
      (snapshot) {
        stdout.writeln('  Metrics: $snapshot');
        alertManager.evaluateMetrics(snapshot);
      },
      onError: (Object e) {
        stderr.writeln('  Metrics error: $e');
      },
    );
  }

  // Handle Ctrl+C gracefully.
  ProcessSignal.sigint.watch().listen((_) {
    stdout.writeln('\nStopping monitor...');
    healthChecker.stop();
    metricsCollector?.stop();
    metricsSub?.cancel();
    healthChecker.close();
    metricsCollector?.close();
    exit(0);
  });

  await for (final status in healthChecker.monitor()) {
    stdout.writeln(status);

    final consecutiveFailures = _countConsecutiveFailures(
      healthChecker.history,
    );
    alertManager.evaluateHealth(
      status,
      consecutiveFailures: consecutiveFailures,
    );
    alertManager.evaluateUptime(healthChecker.uptimePercentage);
  }
}

int _countConsecutiveFailures(List<HealthStatus> history) {
  var count = 0;
  for (var i = history.length - 1; i >= 0; i--) {
    if (!history[i].healthy) {
      count++;
    } else {
      break;
    }
  }
  return count;
}
