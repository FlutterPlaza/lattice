# Monitoring

Lattice includes a monitoring tool (`tools/monitor`) that tracks server health, collects metrics, and manages alerts. The monitoring tool operates over the server's public `/api/v1/health` and `/api/v1/metrics` endpoints only -- it never accesses internal state or cryptographic material.

## Overview

The monitoring system has three components:

- **HealthChecker** -- periodic health probes with configurable intervals and thresholds
- **MetricsCollector** -- polls the `/api/v1/metrics` endpoint and records time-series data
- **AlertManager** -- evaluates alert rules against collected metrics and triggers notifications

## Running the Monitor

```bash
dart run tools/monitor/bin/monitor.dart
```

By default, the monitor connects to `http://localhost:8080` and starts polling every 30 seconds.

## Health Checking

The health checker calls `GET /api/v1/health` and inspects the response:

```json
{
  "status": "ok",
  "uptime": 3600,
  "version": "0.1.0"
}
```

### Health check configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| Interval | 30s | Time between health checks |
| Timeout | 10s | Maximum time to wait for a response |
| Failure threshold | 3 | Consecutive failures before marking unhealthy |
| Recovery threshold | 2 | Consecutive successes to restore healthy status |

### Health states

| State | Meaning |
|-------|---------|
| `healthy` | Server is responsive and returning `status: ok` |
| `degraded` | Server is responsive but returning errors or slow responses |
| `unhealthy` | Server has failed the consecutive failure threshold |
| `unknown` | No health check has completed yet |

## Metrics Collection

The metrics collector polls `GET /api/v1/metrics` and records the following data points:

```json
{
  "users": 42,
  "prekeys": 15,
  "pendingMessages": 3,
  "uptime": 7200
}
```

### Available metrics

| Metric | Type | Description |
|--------|------|-------------|
| `users` | Gauge | Total registered users |
| `prekeys` | Gauge | Currently stored pre-key bundles |
| `pendingMessages` | Gauge | Undelivered key-exchange messages |
| `uptime` | Counter | Server uptime in seconds |
| `healthCheckLatency` | Histogram | Response time of health check requests (ms) |

### Metric retention

By default, the collector stores the last 1000 data points in memory. For long-term storage, integrate with an external time-series database (e.g., Prometheus, InfluxDB).

## Alert Configuration

The alert manager evaluates rules against collected metrics and triggers callbacks when thresholds are crossed.

### Built-in alert rules

| Alert | Condition | Severity |
|-------|-----------|----------|
| Server Down | Health check fails for 3 consecutive checks | Critical |
| High Pending Messages | `pendingMessages > 100` | Warning |
| No Pre-Keys | `prekeys == 0` | Warning |
| High Latency | Health check latency > 5000ms | Warning |

### Custom alert rules

```dart
import 'package:lattice_monitor/lattice_monitor.dart';

final alertManager = AlertManager();

// Add a custom rule
alertManager.addRule(
  AlertRule(
    name: 'Too many users',
    condition: (metrics) => (metrics['users'] as int) > 10000,
    severity: AlertSeverity.warning,
    message: 'User count exceeds 10,000',
  ),
);

// Register a callback
alertManager.onAlert((alert) {
  print('[${alert.severity}] ${alert.name}: ${alert.message}');
  // Send to PagerDuty, Slack, email, etc.
});
```

## CLI Usage

The monitor CLI supports the following commands:

```bash
# Start monitoring with default settings
dart run tools/monitor/bin/monitor.dart

# One-shot health check
dart run tools/monitor/bin/monitor.dart --check

# Custom server URL and interval
dart run tools/monitor/bin/monitor.dart \
  --url http://lattice.example.com:8080 \
  --interval 60
```

| Option | Default | Description |
|--------|---------|-------------|
| `--url` | `http://localhost:8080` | Server base URL |
| `--interval` | `30` | Polling interval in seconds |
| `--check` | `false` | Run a single health check and exit |

## Dashboard

The monitoring tool outputs a summary to the terminal on each poll cycle:

```
=== Lattice Server Monitor ===
Status:   healthy
Uptime:   2h 15m 30s
Version:  0.1.0
Latency:  45ms

--- Metrics ---
Users:            42
Pre-keys:         15
Pending messages: 3

--- Alerts ---
(none)

Last check: 2024-01-15T10:30:00Z
Next check in 30s
```

## Integration with External Systems

### Prometheus

Expose metrics in Prometheus format by querying the `/api/v1/metrics` endpoint with a Prometheus scrape config:

```yaml
scrape_configs:
  - job_name: 'lattice-server'
    metrics_path: '/api/v1/metrics'
    static_configs:
      - targets: ['localhost:8080']
    scrape_interval: 30s
```

> Note: The `/api/v1/metrics` endpoint returns JSON, not Prometheus exposition format. You will need a JSON-to-Prometheus exporter or custom scraper.

### Webhook Alerts

Configure the alert manager to send HTTP webhooks:

```dart
alertManager.onAlert((alert) async {
  await http.post(
    Uri.parse('https://hooks.slack.com/services/...'),
    body: jsonEncode({
      'text': '[${alert.severity}] ${alert.name}: ${alert.message}',
    }),
  );
});
```
