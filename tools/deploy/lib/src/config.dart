import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Deployment target type.
enum DeployTarget {
  /// Local Docker deployment.
  local,

  /// Amazon Web Services.
  aws,

  /// Microsoft Azure.
  azure,

  /// Google Cloud Platform.
  gcp,

  /// Firebase (Cloud Run + Hosting).
  firebase,
}

/// Parses a [DeployTarget] from its name string.
DeployTarget parseDeployTarget(String name) {
  return DeployTarget.values.firstWhere(
    (t) => t.name == name,
    orElse: () => DeployTarget.local,
  );
}

/// Scaling configuration for cloud deployments.
class ScalingConfig {
  /// Creates a [ScalingConfig] with the given thresholds.
  const ScalingConfig({
    this.minInstances = 1,
    this.maxInstances = 3,
    this.cpuThresholdPercent = 70,
    this.memoryThresholdPercent = 80,
  });

  /// Creates a [ScalingConfig] from a map (e.g. parsed YAML).
  factory ScalingConfig.fromMap(Map<String, dynamic> map) {
    return ScalingConfig(
      minInstances: map['min_instances'] as int? ?? 1,
      maxInstances: map['max_instances'] as int? ?? 3,
      cpuThresholdPercent: map['cpu_threshold_percent'] as int? ?? 70,
      memoryThresholdPercent: map['memory_threshold_percent'] as int? ?? 80,
    );
  }

  /// Minimum number of running instances.
  final int minInstances;

  /// Maximum number of running instances.
  final int maxInstances;

  /// CPU usage percentage that triggers scale-up.
  final int cpuThresholdPercent;

  /// Memory usage percentage that triggers scale-up.
  final int memoryThresholdPercent;

  /// Serialises this configuration to a plain map.
  Map<String, dynamic> toMap() => {
    'min_instances': minInstances,
    'max_instances': maxInstances,
    'cpu_threshold_percent': cpuThresholdPercent,
    'memory_threshold_percent': memoryThresholdPercent,
  };
}

/// Server deployment configuration.
class DeployConfig {
  /// Creates a [DeployConfig] with the provided values.
  const DeployConfig({
    this.target = DeployTarget.local,
    this.serverHost = '0.0.0.0',
    this.serverPort = 8080,
    this.storagePath,
    this.dockerImage = 'lattice-server',
    this.registryUrl,
    this.scaling = const ScalingConfig(),
    this.environment = const {},
  });

  /// Creates a [DeployConfig] from a plain map (e.g. parsed YAML).
  factory DeployConfig.fromMap(Map<String, dynamic> map) {
    final envRaw = map['environment'];
    final envMap = <String, String>{};
    if (envRaw is Map) {
      for (final entry in envRaw.entries) {
        envMap[entry.key.toString()] = entry.value.toString();
      }
    }

    final scalingRaw = map['scaling'];
    final scalingMap = <String, dynamic>{};
    if (scalingRaw is Map) {
      for (final entry in scalingRaw.entries) {
        scalingMap[entry.key.toString()] = entry.value;
      }
    }

    return DeployConfig(
      target: parseDeployTarget(map['target'] as String? ?? 'local'),
      serverHost: map['server_host'] as String? ?? '0.0.0.0',
      serverPort: map['server_port'] as int? ?? 8080,
      storagePath: map['storage_path'] as String?,
      dockerImage: map['docker_image'] as String? ?? 'lattice-server',
      registryUrl: map['registry_url'] as String?,
      scaling:
          scalingMap.isEmpty
              ? const ScalingConfig()
              : ScalingConfig.fromMap(scalingMap),
      environment: envMap,
    );
  }

  /// The deployment target platform.
  final DeployTarget target;

  /// Host address the server binds to.
  final String serverHost;

  /// Port the server listens on.
  final int serverPort;

  /// Optional path for persistent storage.
  final String? storagePath;

  /// Docker image name.
  final String? dockerImage;

  /// Container registry URL for pushing images.
  final String? registryUrl;

  /// Auto-scaling configuration.
  final ScalingConfig scaling;

  /// Extra environment variables passed to the container.
  final Map<String, String> environment;

  /// Default path for the configuration file.
  static String get configFilePath =>
      p.join(Platform.environment['HOME'] ?? '.', '.lattice', 'deploy.yaml');

  /// Loads the configuration from [path], defaulting to
  /// `~/.lattice/deploy.yaml`.
  ///
  /// Returns `null` if the file does not exist or cannot be parsed.
  static DeployConfig? load({String? path}) {
    final filePath = path ?? configFilePath;
    final file = File(filePath);
    if (!file.existsSync()) return null;

    try {
      final content = file.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is! YamlMap) return null;

      final map = <String, dynamic>{};
      for (final entry in yaml.entries) {
        map[entry.key.toString()] = entry.value;
      }
      return DeployConfig.fromMap(map);
    } on Exception {
      return null;
    }
  }

  /// Persists the configuration to [path], defaulting to
  /// `~/.lattice/deploy.yaml`.
  Future<void> save({String? path}) async {
    final filePath = path ?? configFilePath;
    final file = File(filePath);
    await file.parent.create(recursive: true);

    final buffer =
        StringBuffer()
          ..writeln('target: ${target.name}')
          ..writeln('server_host: $serverHost')
          ..writeln('server_port: $serverPort');

    if (storagePath != null) {
      buffer.writeln('storage_path: $storagePath');
    }
    if (dockerImage != null) {
      buffer.writeln('docker_image: $dockerImage');
    }
    if (registryUrl != null) {
      buffer.writeln('registry_url: $registryUrl');
    }

    buffer.writeln('scaling:');
    final scalingMap = scaling.toMap();
    for (final entry in scalingMap.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }

    if (environment.isNotEmpty) {
      buffer.writeln('environment:');
      for (final entry in environment.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    await file.writeAsString(buffer.toString());
  }

  /// Serialises this configuration to a plain map.
  Map<String, dynamic> toMap() => {
    'target': target.name,
    'server_host': serverHost,
    'server_port': serverPort,
    if (storagePath != null) 'storage_path': storagePath,
    'docker_image': dockerImage,
    if (registryUrl != null) 'registry_url': registryUrl,
    'scaling': scaling.toMap(),
    'environment': environment,
  };
}
