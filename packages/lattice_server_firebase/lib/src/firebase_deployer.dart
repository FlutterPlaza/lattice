import 'dart:io';

import 'firebase_config.dart';

/// Result of a Firebase deployment operation.
class FirebaseDeployResult {
  /// Creates a [FirebaseDeployResult].
  const FirebaseDeployResult({
    required this.success,
    required this.message,
    this.serviceUrl,
  });

  /// Whether the operation succeeded.
  final bool success;

  /// Human-readable description of the outcome.
  final String message;

  /// The URL where the service can be reached, if applicable.
  final String? serviceUrl;

  @override
  String toString() {
    final status = success ? 'SUCCESS' : 'FAILURE';
    final url = serviceUrl != null ? ' ($serviceUrl)' : '';
    return '[$status] $message$url';
  }
}

/// Firebase Cloud Run deployer for the Lattice server.
class FirebaseDeployer {
  /// Creates a [FirebaseDeployer] with the given [config].
  const FirebaseDeployer(this.config);

  /// The Firebase deployment configuration.
  final FirebaseConfig config;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Validates that the required CLI tools are installed.
  ///
  /// Checks for `firebase`, `gcloud`, and `docker` on the system PATH.
  Future<FirebaseDeployResult> validatePrerequisites() async {
    final tools = <String, List<String>>{
      'firebase': ['--version'],
      'gcloud': ['--version'],
      'docker': ['--version'],
    };

    final missing = <String>[];
    for (final entry in tools.entries) {
      try {
        final result = await _run(entry.key, entry.value);
        if (result.exitCode != 0) {
          missing.add(entry.key);
        }
      } on Exception {
        missing.add(entry.key);
      }
    }

    if (missing.isEmpty) {
      return const FirebaseDeployResult(
        success: true,
        message: 'All prerequisites met (firebase, gcloud, docker).',
      );
    }

    return FirebaseDeployResult(
      success: false,
      message:
          'Missing prerequisites: ${missing.join(', ')}. '
          'Install them before deploying.',
    );
  }

  /// Generates the `firebase.json` content for Cloud Run hosting proxy.
  String generateFirebaseJson() {
    return '{\n'
        '  "hosting": {\n'
        '    "public": "public",\n'
        '    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],\n'
        '    "rewrites": [\n'
        '      {\n'
        '        "source": "/api/**",\n'
        '        "run": {\n'
        '          "serviceId": "${config.serviceName}",\n'
        '          "region": "${config.region}"\n'
        '        }\n'
        '      }\n'
        '    ]\n'
        '  }\n'
        '}';
  }

  /// Generates the ordered list of shell commands for deployment.
  List<String> generateDeployCommands() {
    final envFlags = config.environment.entries
        .map((e) => '--set-env-vars ${e.key}=${e.value}')
        .join(' ');

    final envSuffix = envFlags.isEmpty ? '' : ' $envFlags';

    final buildCommand =
        'gcloud builds submit '
        '--tag gcr.io/${config.projectId}/${config.serviceName}';

    final deployCommand =
        'gcloud run deploy ${config.serviceName} '
        '--image gcr.io/${config.projectId}/${config.serviceName} '
        '--platform managed '
        '--region ${config.region} '
        '--port ${config.port} '
        '--min-instances ${config.minInstances} '
        '--max-instances ${config.maxInstances} '
        '--memory ${config.memory} '
        '--cpu ${config.cpu}'
        '$envSuffix';

    return [buildCommand, deployCommand, 'firebase deploy --only hosting'];
  }

  /// Deploys the Lattice server to Firebase Cloud Run.
  ///
  /// When [dryRun] is `true`, no side-effects are performed; the method only
  /// reports what *would* be done.
  Future<FirebaseDeployResult> deploy({bool dryRun = false}) async {
    if (dryRun) {
      final commands = generateDeployCommands();
      final preview = commands.map((c) => '  \$ $c').join('\n');
      return FirebaseDeployResult(
        success: true,
        message: 'Dry-run for Firebase Cloud Run deployment:\n$preview',
      );
    }

    final commands = generateDeployCommands();
    for (final command in commands) {
      final parts = command.split(' ');
      final executable = parts.first;
      final args = parts.sublist(1);

      try {
        final result = await _run(executable, args);
        if (result.exitCode != 0) {
          return FirebaseDeployResult(
            success: false,
            message:
                'Command failed: $command\n'
                '${result.stderr.toString().trim()}',
          );
        }
      } on Exception catch (e) {
        return FirebaseDeployResult(
          success: false,
          message: 'Deployment error running "$command": $e',
        );
      }
    }

    final serviceUrl = 'https://${config.serviceName}-${config.region}.run.app';

    return FirebaseDeployResult(
      success: true,
      message: 'Firebase Cloud Run deployment complete.',
      serviceUrl: serviceUrl,
    );
  }

  /// Checks the health of the deployed service by hitting its health endpoint.
  Future<FirebaseDeployResult> healthCheck() async {
    final serviceUrl = 'https://${config.serviceName}-${config.region}.run.app';
    final healthUrl = '$serviceUrl/api/v1/health';

    try {
      final result = await _run('curl', [
        '-s',
        '-o',
        '/dev/null',
        '-w',
        '%{http_code}',
        '--max-time',
        '5',
        healthUrl,
      ]);

      final statusCode = result.stdout.toString().trim();
      if (statusCode == '200') {
        return FirebaseDeployResult(
          success: true,
          message: 'Health check passed (HTTP 200).',
          serviceUrl: serviceUrl,
        );
      }
      return FirebaseDeployResult(
        success: false,
        message: 'Health check failed (HTTP $statusCode).',
        serviceUrl: serviceUrl,
      );
    } on Exception catch (e) {
      return FirebaseDeployResult(
        success: false,
        message: 'Health check error: $e',
      );
    }
  }

  /// Tears down the Cloud Run service and removes Firebase hosting config.
  Future<FirebaseDeployResult> teardown() async {
    try {
      final deleteResult = await _run('gcloud', [
        'run',
        'services',
        'delete',
        config.serviceName,
        '--region',
        config.region,
        '--quiet',
      ]);

      if (deleteResult.exitCode != 0) {
        final stderr = deleteResult.stderr.toString().trim();
        return FirebaseDeployResult(
          success: false,
          message: 'Failed to delete Cloud Run service: $stderr',
        );
      }

      return FirebaseDeployResult(
        success: true,
        message:
            'Cloud Run service "${config.serviceName}" deleted '
            'from region "${config.region}".',
      );
    } on Exception catch (e) {
      return FirebaseDeployResult(
        success: false,
        message: 'Teardown error: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Runs a shell command and returns the [ProcessResult].
  Future<ProcessResult> _run(String command, List<String> args) async {
    return Process.run(command, args);
  }
}
