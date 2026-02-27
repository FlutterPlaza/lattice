import 'health_checker.dart';
import 'metrics_collector.dart';

/// Alert severity levels.
enum AlertSeverity {
  /// Informational alert.
  info,

  /// Warning alert.
  warning,

  /// Critical alert.
  critical,
}

/// An alert triggered by a threshold breach.
class Alert {
  /// Creates a new [Alert].
  const Alert({
    required this.severity,
    required this.message,
    required this.triggeredAt,
  });

  /// The severity of this alert.
  final AlertSeverity severity;

  /// A human-readable description of the alert.
  final String message;

  /// When the alert was triggered.
  final DateTime triggeredAt;

  @override
  String toString() => '[${severity.name.toUpperCase()}] $message';
}

/// Configuration for alert thresholds.
class AlertThreshold {
  /// Creates a new [AlertThreshold] with the given thresholds.
  const AlertThreshold({
    this.maxConsecutiveFailures = 3,
    this.maxPendingMessages = 1000,
    this.minUptimePercentage = 99.0,
  });

  /// Maximum number of consecutive health check failures before a critical
  /// alert is raised.
  final int? maxConsecutiveFailures;

  /// Maximum number of pending messages before a warning alert is raised.
  final int? maxPendingMessages;

  /// Minimum uptime percentage before a critical alert is raised.
  final double? minUptimePercentage;
}

/// Manages alerts based on health and metrics data.
class AlertManager {
  /// Creates a new [AlertManager].
  AlertManager({this.threshold = const AlertThreshold(), this.onAlert});

  /// The threshold configuration for triggering alerts.
  final AlertThreshold threshold;

  /// Optional callback invoked whenever a new alert is added.
  final void Function(Alert)? onAlert;

  final List<Alert> _alerts = [];

  /// Evaluates a [HealthStatus] against the configured thresholds.
  ///
  /// If the status is unhealthy and [consecutiveFailures] meets or exceeds
  /// the configured maximum, a critical alert is raised. Otherwise a warning
  /// is raised.
  void evaluateHealth(HealthStatus status, {int consecutiveFailures = 0}) {
    if (!status.healthy) {
      if (consecutiveFailures >= (threshold.maxConsecutiveFailures ?? 3)) {
        _addAlert(
          AlertSeverity.critical,
          'Server ${status.endpoint} has $consecutiveFailures '
          'consecutive failures',
        );
      } else {
        _addAlert(
          AlertSeverity.warning,
          'Server ${status.endpoint} health check failed',
        );
      }
    }
  }

  /// Evaluates a [MetricsSnapshot] against the configured thresholds.
  void evaluateMetrics(MetricsSnapshot metrics) {
    if (threshold.maxPendingMessages != null &&
        metrics.pendingMessageCount > threshold.maxPendingMessages!) {
      _addAlert(
        AlertSeverity.warning,
        '${metrics.pendingMessageCount} pending messages exceeds threshold',
      );
    }
  }

  /// Evaluates the given [uptimePercentage] against the configured threshold.
  void evaluateUptime(double uptimePercentage) {
    if (threshold.minUptimePercentage != null &&
        uptimePercentage < threshold.minUptimePercentage!) {
      _addAlert(
        AlertSeverity.critical,
        'Uptime ${uptimePercentage.toStringAsFixed(1)}% below threshold',
      );
    }
  }

  /// Returns an unmodifiable list of all alerts that have been triggered.
  List<Alert> get alerts => List.unmodifiable(_alerts);

  /// Clears all triggered alerts.
  void clearAlerts() {
    _alerts.clear();
  }

  void _addAlert(AlertSeverity severity, String message) {
    final alert = Alert(
      severity: severity,
      message: message,
      triggeredAt: DateTime.now(),
    );
    _alerts.add(alert);
    onAlert?.call(alert);
  }
}
