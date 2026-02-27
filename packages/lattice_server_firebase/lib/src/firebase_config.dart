/// Firebase project configuration for Cloud Run deployment.
class FirebaseConfig {
  /// Creates a [FirebaseConfig] with the given project settings.
  const FirebaseConfig({
    required this.projectId,
    this.region = 'us-central1',
    this.serviceName = 'lattice-server',
    this.port = 8080,
    this.minInstances = 0,
    this.maxInstances = 3,
    this.memory = '512Mi',
    this.cpu = '1',
    this.environment = const {},
  });

  /// Creates a [FirebaseConfig] from a plain map (e.g. parsed YAML/JSON).
  factory FirebaseConfig.fromMap(Map<String, dynamic> map) {
    final envRaw = map['environment'];
    final envMap = <String, String>{};
    if (envRaw is Map) {
      for (final entry in envRaw.entries) {
        envMap[entry.key.toString()] = entry.value.toString();
      }
    }

    return FirebaseConfig(
      projectId: map['project_id'] as String,
      region: map['region'] as String? ?? 'us-central1',
      serviceName: map['service_name'] as String? ?? 'lattice-server',
      port: map['port'] as int? ?? 8080,
      minInstances: map['min_instances'] as int? ?? 0,
      maxInstances: map['max_instances'] as int? ?? 3,
      memory: map['memory'] as String? ?? '512Mi',
      cpu: map['cpu'] as String? ?? '1',
      environment: envMap,
    );
  }

  /// The Firebase/GCP project identifier.
  final String projectId;

  /// The Cloud Run region (e.g. `us-central1`).
  final String region;

  /// The Cloud Run service name.
  final String serviceName;

  /// The port the server listens on inside the container.
  final int port;

  /// Minimum number of Cloud Run instances (0 allows scale-to-zero).
  final int minInstances;

  /// Maximum number of Cloud Run instances.
  final int maxInstances;

  /// Memory allocation per instance (e.g. `512Mi`, `1Gi`).
  final String memory;

  /// CPU allocation per instance (e.g. `1`, `2`).
  final String cpu;

  /// Extra environment variables passed to the container.
  final Map<String, String> environment;

  /// Serialises this configuration to a plain map.
  Map<String, dynamic> toMap() => {
    'project_id': projectId,
    'region': region,
    'service_name': serviceName,
    'port': port,
    'min_instances': minInstances,
    'max_instances': maxInstances,
    'memory': memory,
    'cpu': cpu,
    'environment': environment,
  };
}
