import 'dart:io';

import 'package:args/args.dart';
import 'package:lattice_deploy/lattice_deploy.dart';

void main(List<String> args) async {
  final deployCmd =
      ArgParser()..addFlag(
        'dry-run',
        negatable: false,
        help: 'Show what would be done without executing.',
      );

  final teardownCmd = ArgParser();

  final healthCmd =
      ArgParser()..addOption(
        'endpoint',
        abbr: 'e',
        help: 'URL to check (e.g. http://localhost:8080).',
      );

  final configCmd =
      ArgParser()..addFlag(
        'show',
        negatable: false,
        help: 'Print the current configuration.',
      );

  final parser =
      ArgParser()
        ..addCommand('deploy', deployCmd)
        ..addCommand('teardown', teardownCmd)
        ..addCommand('health', healthCmd)
        ..addCommand('config', configCmd)
        ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
        ..addOption(
          'target',
          abbr: 't',
          allowed: ['local', 'aws', 'azure', 'gcp', 'firebase'],
          defaultsTo: 'local',
          help: 'Deployment target.',
        )
        ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Server port.')
        ..addOption(
          'image',
          defaultsTo: 'lattice-server',
          help: 'Docker image name.',
        );

  late final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  if (results.flag('help') || results.command == null) {
    _printUsage(parser);
    return;
  }

  // Build configuration from saved file, then override with CLI flags.
  final saved = DeployConfig.load() ?? const DeployConfig();
  final config = DeployConfig(
    target: parseDeployTarget(results.option('target') ?? saved.target.name),
    serverHost: saved.serverHost,
    serverPort: int.tryParse(results.option('port') ?? '') ?? saved.serverPort,
    storagePath: saved.storagePath,
    dockerImage: results.option('image') ?? saved.dockerImage,
    registryUrl: saved.registryUrl,
    scaling: saved.scaling,
    environment: saved.environment,
  );

  final deployer = Deployer(config);

  switch (results.command!.name) {
    case 'deploy':
      final dryRun = results.command!.flag('dry-run');
      final prereq = await deployer.validatePrerequisites();
      _print(prereq);
      if (!prereq.success && !dryRun) {
        exitCode = 1;
        return;
      }
      final deployResult = await deployer.deploy(dryRun: dryRun);
      _print(deployResult);
      if (!deployResult.success) exitCode = 1;

    case 'teardown':
      final result = await deployer.teardown();
      _print(result);
      if (!result.success) exitCode = 1;

    case 'health':
      final endpoint =
          results.command!.option('endpoint') ??
          'http://${config.serverHost}:${config.serverPort}';
      final result = await deployer.healthCheck(endpoint);
      _print(result);
      if (!result.success) exitCode = 1;

    case 'config':
      if (results.command!.flag('show')) {
        stdout.writeln('Current configuration:');
        config.toMap().forEach((key, value) {
          stdout.writeln('  $key: $value');
        });
      } else {
        await config.save();
        stdout.writeln('Configuration saved to ${DeployConfig.configFilePath}');
      }

    default:
      _printUsage(parser);
  }
}

void _printUsage(ArgParser parser) {
  stdout.writeln('Lattice Deploy CLI');
  stdout.writeln('');
  stdout.writeln('Usage: dart run deploy <command> [options]');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln('  deploy     Deploy the Lattice server');
  stdout.writeln('  teardown   Tear down a local deployment');
  stdout.writeln('  health     Run a health check');
  stdout.writeln('  config     View or save configuration');
  stdout.writeln('');
  stdout.writeln(parser.usage);
}

void _print(DeployResult result) {
  if (result.success) {
    stdout.writeln(result);
  } else {
    stderr.writeln(result);
  }
}
