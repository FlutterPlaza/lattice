import 'dart:io';

import 'config.dart';

/// Result of a deployment operation.
class DeployResult {
  /// Creates a [DeployResult].
  const DeployResult({
    required this.success,
    required this.message,
    this.endpoint,
  });

  /// Whether the operation succeeded.
  final bool success;

  /// Human-readable description of the outcome.
  final String message;

  /// The URL where the service can be reached, if applicable.
  final String? endpoint;

  @override
  String toString() {
    final status = success ? 'SUCCESS' : 'FAILURE';
    final ep = endpoint != null ? ' ($endpoint)' : '';
    return '[$status] $message$ep';
  }
}

/// Deploys the Lattice server to the configured target.
class Deployer {
  /// Creates a [Deployer] with the given [config].
  const Deployer(this.config);

  /// The deployment configuration.
  final DeployConfig config;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Validates that the prerequisites for [config.target] are met.
  Future<DeployResult> validatePrerequisites() async {
    switch (config.target) {
      case DeployTarget.local:
        return _validateDocker();
      case DeployTarget.aws:
        return _validateAws();
      case DeployTarget.azure:
        return _validateAzure();
      case DeployTarget.gcp:
        return _validateGcp();
      case DeployTarget.firebase:
        return _validateFirebase();
    }
  }

  /// Deploys the server to the configured target.
  ///
  /// When [dryRun] is `true`, no side-effects are performed; the method only
  /// reports what *would* be done.
  Future<DeployResult> deploy({bool dryRun = false}) async {
    if (dryRun) return _dryRun();

    switch (config.target) {
      case DeployTarget.local:
        return _deployLocal();
      case DeployTarget.aws:
        return _deployAws();
      case DeployTarget.azure:
        return _deployAzure();
      case DeployTarget.gcp:
        return _deployGcp();
      case DeployTarget.firebase:
        return _deployFirebase();
    }
  }

  /// Runs a health check against a deployed server at [endpoint].
  Future<DeployResult> healthCheck(String endpoint) async {
    try {
      final result = await _run('curl', [
        '-s',
        '-o',
        '/dev/null',
        '-w',
        '%{http_code}',
        '--max-time',
        '5',
        endpoint,
      ]);

      final statusCode = result.stdout.toString().trim();
      if (statusCode == '200') {
        return DeployResult(
          success: true,
          message: 'Health check passed (HTTP 200).',
          endpoint: endpoint,
        );
      }
      return DeployResult(
        success: false,
        message: 'Health check failed (HTTP $statusCode).',
        endpoint: endpoint,
      );
    } on Exception catch (e) {
      return DeployResult(success: false, message: 'Health check error: $e');
    }
  }

  /// Tears down a local Docker deployment.
  Future<DeployResult> teardown() async {
    final image = config.dockerImage ?? 'lattice-server';
    try {
      // Find running container by image name.
      final ps = await _run('docker', [
        'ps',
        '-q',
        '--filter',
        'ancestor=$image',
      ]);
      final containerId = ps.stdout.toString().trim();
      if (containerId.isEmpty) {
        return const DeployResult(
          success: true,
          message: 'No running container found. Nothing to tear down.',
        );
      }

      await _run('docker', ['stop', containerId]);
      await _run('docker', ['rm', containerId]);

      return DeployResult(
        success: true,
        message: 'Container $containerId stopped and removed.',
      );
    } on Exception catch (e) {
      return DeployResult(success: false, message: 'Teardown failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Deployment targets
  // ---------------------------------------------------------------------------

  Future<DeployResult> _deployLocal() async {
    final image = config.dockerImage ?? 'lattice-server';
    try {
      // 1. Build the Docker image.
      final build = await _run('docker', ['build', '-t', image, '.']);
      if (build.exitCode != 0) {
        return DeployResult(
          success: false,
          message: 'Docker build failed: ${build.stderr}',
        );
      }

      // 2. Run the container.
      final portMapping = '${config.serverPort}:${config.serverPort}';
      final envArgs = <String>[];
      for (final entry in config.environment.entries) {
        envArgs.addAll(['-e', '${entry.key}=${entry.value}']);
      }

      final run = await _run('docker', [
        'run',
        '-d',
        '-p',
        portMapping,
        ...envArgs,
        image,
      ]);
      if (run.exitCode != 0) {
        return DeployResult(
          success: false,
          message: 'Docker run failed: ${run.stderr}',
        );
      }

      final endpoint = 'http://${config.serverHost}:${config.serverPort}';
      return DeployResult(
        success: true,
        message: 'Local deployment started.',
        endpoint: endpoint,
      );
    } on Exception catch (e) {
      return DeployResult(
        success: false,
        message: 'Local deployment error: $e',
      );
    }
  }

  Future<DeployResult> _deployAws() async {
    final image = config.dockerImage ?? 'lattice-server';
    final registry =
        config.registryUrl ?? '<AWS_ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com';
    final scaling = config.scaling;

    final taskDef =
        'aws ecs register-task-definition '
        '--family lattice-task '
        '--container-definitions \'[{"name":"$image","image":"$registry/$image:latest","portMappings":[{"containerPort":${config.serverPort}}],"memory":512,"cpu":256}]\'';
    final createSvc =
        'aws ecs create-service '
        '--cluster lattice-cluster '
        '--service-name lattice-service '
        '--task-definition lattice-task '
        '--desired-count ${scaling.minInstances} '
        '--launch-type FARGATE';

    final commands = [
      'docker build -t $image .',
      'docker tag $image $registry/$image:latest',
      'aws ecr get-login-password | docker login --username AWS --password-stdin $registry',
      'docker push $registry/$image:latest',
      'aws ecs create-cluster --cluster-name lattice-cluster',
      taskDef,
      createSvc,
    ];

    return DeployResult(
      success: true,
      message:
          'AWS deployment commands:\n${commands.map((c) => '  \$ $c').join('\n')}',
    );
  }

  Future<DeployResult> _deployAzure() async {
    final image = config.dockerImage ?? 'lattice-server';
    final registry = config.registryUrl ?? '<REGISTRY_NAME>.azurecr.io';
    final scaling = config.scaling;

    final createApp =
        'az containerapp create '
        '--name lattice-app '
        '--resource-group lattice-rg '
        '--image $registry/$image:latest '
        '--target-port ${config.serverPort} '
        '--min-replicas ${scaling.minInstances} '
        '--max-replicas ${scaling.maxInstances} '
        '--cpu 0.25 --memory 0.5Gi';

    final commands = [
      'docker build -t $image .',
      'docker tag $image $registry/$image:latest',
      'az acr login --name <REGISTRY_NAME>',
      'docker push $registry/$image:latest',
      createApp,
    ];

    return DeployResult(
      success: true,
      message:
          'Azure deployment commands:\n${commands.map((c) => '  \$ $c').join('\n')}',
    );
  }

  Future<DeployResult> _deployGcp() async {
    final image = config.dockerImage ?? 'lattice-server';
    final registry = config.registryUrl ?? 'gcr.io/<PROJECT_ID>';
    final scaling = config.scaling;

    final runDeploy =
        'gcloud run deploy lattice-service '
        '--image $registry/$image:latest '
        '--port ${config.serverPort} '
        '--min-instances ${scaling.minInstances} '
        '--max-instances ${scaling.maxInstances} '
        '--allow-unauthenticated';

    final commands = [
      'docker build -t $image .',
      'docker tag $image $registry/$image:latest',
      'gcloud auth configure-docker',
      'docker push $registry/$image:latest',
      runDeploy,
    ];

    return DeployResult(
      success: true,
      message:
          'GCP deployment commands:\n${commands.map((c) => '  \$ $c').join('\n')}',
    );
  }

  Future<DeployResult> _deployFirebase() async {
    final image = config.dockerImage ?? 'lattice-server';
    final registry = config.registryUrl ?? 'gcr.io/<PROJECT_ID>';
    final scaling = config.scaling;

    final runDeploy =
        'gcloud run deploy lattice-service '
        '--image $registry/$image:latest '
        '--port ${config.serverPort} '
        '--min-instances ${scaling.minInstances} '
        '--max-instances ${scaling.maxInstances} '
        '--allow-unauthenticated';

    final commands = [
      'docker build -t $image .',
      'gcloud builds submit --tag $registry/$image:latest',
      runDeploy,
      'firebase deploy --only hosting',
    ];

    return DeployResult(
      success: true,
      message:
          'Firebase deployment commands:\n${commands.map((c) => '  \$ $c').join('\n')}',
    );
  }

  // ---------------------------------------------------------------------------
  // Dry run
  // ---------------------------------------------------------------------------

  DeployResult _dryRun() {
    final image = config.dockerImage ?? 'lattice-server';
    final lines = <String>[
      'Dry-run for target: ${config.target.name}',
      'Image: $image',
      'Host: ${config.serverHost}:${config.serverPort}',
      'Scaling: ${config.scaling.minInstances}-${config.scaling.maxInstances} instances',
    ];
    if (config.registryUrl != null) {
      lines.add('Registry: ${config.registryUrl}');
    }
    if (config.environment.isNotEmpty) {
      lines.add('Environment: ${config.environment.keys.join(', ')}');
    }
    return DeployResult(success: true, message: lines.join('\n'));
  }

  // ---------------------------------------------------------------------------
  // Prerequisite validation
  // ---------------------------------------------------------------------------

  Future<DeployResult> _validateDocker() async {
    try {
      final result = await _run('docker', ['--version']);
      if (result.exitCode == 0) {
        return DeployResult(
          success: true,
          message: 'Docker found: ${result.stdout.toString().trim()}',
        );
      }
      return const DeployResult(
        success: false,
        message: 'Docker is not installed or not in PATH.',
      );
    } on Exception {
      return const DeployResult(
        success: false,
        message: 'Docker is not installed or not in PATH.',
      );
    }
  }

  Future<DeployResult> _validateAws() async {
    try {
      final result = await _run('aws', ['--version']);
      if (result.exitCode == 0) {
        return DeployResult(
          success: true,
          message: 'AWS CLI found: ${result.stdout.toString().trim()}',
        );
      }
      return const DeployResult(
        success: false,
        message: 'AWS CLI is not installed or not in PATH.',
      );
    } on Exception {
      return const DeployResult(
        success: false,
        message: 'AWS CLI is not installed or not in PATH.',
      );
    }
  }

  Future<DeployResult> _validateAzure() async {
    try {
      final result = await _run('az', ['--version']);
      if (result.exitCode == 0) {
        return DeployResult(
          success: true,
          message: 'Azure CLI found: ${result.stdout.toString().trim()}',
        );
      }
      return const DeployResult(
        success: false,
        message: 'Azure CLI (az) is not installed or not in PATH.',
      );
    } on Exception {
      return const DeployResult(
        success: false,
        message: 'Azure CLI (az) is not installed or not in PATH.',
      );
    }
  }

  Future<DeployResult> _validateGcp() async {
    try {
      final result = await _run('gcloud', ['--version']);
      if (result.exitCode == 0) {
        return DeployResult(
          success: true,
          message: 'GCP CLI found: ${result.stdout.toString().trim()}',
        );
      }
      return const DeployResult(
        success: false,
        message: 'Google Cloud SDK (gcloud) is not installed or not in PATH.',
      );
    } on Exception {
      return const DeployResult(
        success: false,
        message: 'Google Cloud SDK (gcloud) is not installed or not in PATH.',
      );
    }
  }

  Future<DeployResult> _validateFirebase() async {
    try {
      final firebase = await _run('firebase', ['--version']);
      final gcloud = await _run('gcloud', ['--version']);
      if (firebase.exitCode == 0 && gcloud.exitCode == 0) {
        return DeployResult(
          success: true,
          message: 'Firebase CLI found: ${firebase.stdout.toString().trim()}',
        );
      }
      return const DeployResult(
        success: false,
        message:
            'Firebase CLI or Google Cloud SDK is not installed or not in PATH.',
      );
    } on Exception {
      return const DeployResult(
        success: false,
        message:
            'Firebase CLI or Google Cloud SDK is not installed or not in PATH.',
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
