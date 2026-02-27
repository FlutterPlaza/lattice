import 'dart:io';

import 'package:lattice_deploy/lattice_deploy.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // DeployTarget
  // ---------------------------------------------------------------------------
  group('DeployTarget', () {
    test('has all expected values', () {
      expect(DeployTarget.values, hasLength(5));
      expect(DeployTarget.values, contains(DeployTarget.local));
      expect(DeployTarget.values, contains(DeployTarget.aws));
      expect(DeployTarget.values, contains(DeployTarget.azure));
      expect(DeployTarget.values, contains(DeployTarget.gcp));
      expect(DeployTarget.values, contains(DeployTarget.firebase));
    });

    test('parseDeployTarget returns correct target', () {
      expect(parseDeployTarget('local'), DeployTarget.local);
      expect(parseDeployTarget('aws'), DeployTarget.aws);
      expect(parseDeployTarget('azure'), DeployTarget.azure);
      expect(parseDeployTarget('gcp'), DeployTarget.gcp);
    });

    test('parseDeployTarget falls back to local for unknown input', () {
      expect(parseDeployTarget('unknown'), DeployTarget.local);
      expect(parseDeployTarget(''), DeployTarget.local);
    });
  });

  // ---------------------------------------------------------------------------
  // ScalingConfig
  // ---------------------------------------------------------------------------
  group('ScalingConfig', () {
    test('default values', () {
      const s = ScalingConfig();
      expect(s.minInstances, 1);
      expect(s.maxInstances, 3);
      expect(s.cpuThresholdPercent, 70);
      expect(s.memoryThresholdPercent, 80);
    });

    test('custom values', () {
      const s = ScalingConfig(
        minInstances: 2,
        maxInstances: 10,
        cpuThresholdPercent: 90,
        memoryThresholdPercent: 95,
      );
      expect(s.minInstances, 2);
      expect(s.maxInstances, 10);
      expect(s.cpuThresholdPercent, 90);
      expect(s.memoryThresholdPercent, 95);
    });

    test('toMap produces expected keys', () {
      const s = ScalingConfig();
      final map = s.toMap();
      expect(map, containsPair('min_instances', 1));
      expect(map, containsPair('max_instances', 3));
      expect(map, containsPair('cpu_threshold_percent', 70));
      expect(map, containsPair('memory_threshold_percent', 80));
    });

    test('fromMap round-trip', () {
      const original = ScalingConfig(
        minInstances: 5,
        maxInstances: 20,
        cpuThresholdPercent: 60,
        memoryThresholdPercent: 75,
      );
      final restored = ScalingConfig.fromMap(original.toMap());
      expect(restored.minInstances, original.minInstances);
      expect(restored.maxInstances, original.maxInstances);
      expect(restored.cpuThresholdPercent, original.cpuThresholdPercent);
      expect(restored.memoryThresholdPercent, original.memoryThresholdPercent);
    });

    test('fromMap uses defaults for missing keys', () {
      final s = ScalingConfig.fromMap(<String, dynamic>{});
      expect(s.minInstances, 1);
      expect(s.maxInstances, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // DeployConfig
  // ---------------------------------------------------------------------------
  group('DeployConfig', () {
    test('default construction', () {
      const c = DeployConfig();
      expect(c.target, DeployTarget.local);
      expect(c.serverHost, '0.0.0.0');
      expect(c.serverPort, 8080);
      expect(c.storagePath, isNull);
      expect(c.dockerImage, 'lattice-server');
      expect(c.registryUrl, isNull);
      expect(c.environment, isEmpty);
    });

    test('toMap contains expected keys', () {
      const c = DeployConfig(
        target: DeployTarget.aws,
        serverPort: 9090,
        registryUrl: 'https://registry.example.com',
        environment: {'KEY': 'value'},
      );
      final map = c.toMap();
      expect(map['target'], 'aws');
      expect(map['server_port'], 9090);
      expect(map['registry_url'], 'https://registry.example.com');
      expect(map['environment'], {'KEY': 'value'});
      expect(map, contains('scaling'));
    });

    test('fromMap round-trip', () {
      const original = DeployConfig(
        target: DeployTarget.gcp,
        serverHost: '127.0.0.1',
        serverPort: 3000,
        storagePath: '/data',
        dockerImage: 'my-image',
        registryUrl: 'gcr.io/my-project',
        scaling: ScalingConfig(minInstances: 2, maxInstances: 8),
        environment: {'FOO': 'bar', 'BAZ': 'qux'},
      );
      final restored = DeployConfig.fromMap(original.toMap());
      expect(restored.target, original.target);
      expect(restored.serverHost, original.serverHost);
      expect(restored.serverPort, original.serverPort);
      expect(restored.storagePath, original.storagePath);
      expect(restored.dockerImage, original.dockerImage);
      expect(restored.registryUrl, original.registryUrl);
      expect(restored.scaling.minInstances, original.scaling.minInstances);
      expect(restored.scaling.maxInstances, original.scaling.maxInstances);
      expect(restored.environment, original.environment);
    });

    test('fromMap uses defaults for missing keys', () {
      final c = DeployConfig.fromMap(<String, dynamic>{});
      expect(c.target, DeployTarget.local);
      expect(c.serverHost, '0.0.0.0');
      expect(c.serverPort, 8080);
      expect(c.dockerImage, 'lattice-server');
    });

    group('save and load', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('deploy_test_');
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('save then load round-trip', () async {
        final filePath = p.join(tempDir.path, 'deploy.yaml');

        const config = DeployConfig(
          target: DeployTarget.azure,
          serverPort: 4000,
          dockerImage: 'test-image',
          storagePath: '/tmp/storage',
          registryUrl: 'myregistry.azurecr.io',
          scaling: ScalingConfig(minInstances: 2, maxInstances: 5),
          environment: {'DB_HOST': 'localhost'},
        );

        await config.save(path: filePath);

        final loaded = DeployConfig.load(path: filePath);
        expect(loaded, isNotNull);
        expect(loaded!.target, DeployTarget.azure);
        expect(loaded.serverPort, 4000);
        expect(loaded.dockerImage, 'test-image');
        expect(loaded.storagePath, '/tmp/storage');
        expect(loaded.registryUrl, 'myregistry.azurecr.io');
        expect(loaded.scaling.minInstances, 2);
        expect(loaded.scaling.maxInstances, 5);
        expect(loaded.environment['DB_HOST'], 'localhost');
      });

      test('load returns null for missing file', () {
        final filePath = p.join(tempDir.path, 'nonexistent.yaml');
        final loaded = DeployConfig.load(path: filePath);
        expect(loaded, isNull);
      });

      test('save creates parent directories', () async {
        final filePath = p.join(tempDir.path, 'a', 'b', 'deploy.yaml');
        const config = DeployConfig();
        await config.save(path: filePath);
        expect(File(filePath).existsSync(), isTrue);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // DeployResult
  // ---------------------------------------------------------------------------
  group('DeployResult', () {
    test('toString for success', () {
      const r = DeployResult(
        success: true,
        message: 'Deployed',
        endpoint: 'http://localhost:8080',
      );
      expect(r.toString(), contains('SUCCESS'));
      expect(r.toString(), contains('Deployed'));
      expect(r.toString(), contains('http://localhost:8080'));
    });

    test('toString for failure without endpoint', () {
      const r = DeployResult(success: false, message: 'Failed');
      expect(r.toString(), contains('FAILURE'));
      expect(r.toString(), contains('Failed'));
    });
  });

  // ---------------------------------------------------------------------------
  // Deployer
  // ---------------------------------------------------------------------------
  group('Deployer', () {
    group('dry-run', () {
      test('local dry-run reports image and port', () async {
        const config = DeployConfig(
          target: DeployTarget.local,
          serverPort: 9090,
          dockerImage: 'my-img',
        );
        const deployer = Deployer(config);
        final result = await deployer.deploy(dryRun: true);

        expect(result.success, isTrue);
        expect(result.message, contains('local'));
        expect(result.message, contains('my-img'));
        expect(result.message, contains('9090'));
      });

      test('aws dry-run reports target', () async {
        const config = DeployConfig(target: DeployTarget.aws);
        const deployer = Deployer(config);
        final result = await deployer.deploy(dryRun: true);

        expect(result.success, isTrue);
        expect(result.message, contains('aws'));
      });

      test('azure dry-run reports target', () async {
        const config = DeployConfig(target: DeployTarget.azure);
        const deployer = Deployer(config);
        final result = await deployer.deploy(dryRun: true);

        expect(result.success, isTrue);
        expect(result.message, contains('azure'));
      });

      test('gcp dry-run reports target', () async {
        const config = DeployConfig(target: DeployTarget.gcp);
        const deployer = Deployer(config);
        final result = await deployer.deploy(dryRun: true);

        expect(result.success, isTrue);
        expect(result.message, contains('gcp'));
      });

      test('dry-run includes registry when set', () async {
        const config = DeployConfig(
          target: DeployTarget.aws,
          registryUrl: 'ecr.example.com',
        );
        const deployer = Deployer(config);
        final result = await deployer.deploy(dryRun: true);

        expect(result.message, contains('ecr.example.com'));
      });

      test('dry-run includes environment key names', () async {
        const config = DeployConfig(
          target: DeployTarget.local,
          environment: {'SECRET': 'hidden'},
        );
        const deployer = Deployer(config);
        final result = await deployer.deploy(dryRun: true);

        expect(result.message, contains('SECRET'));
      });
    });

    group('validatePrerequisites', () {
      test('local validation checks docker', () async {
        const config = DeployConfig(target: DeployTarget.local);
        const deployer = Deployer(config);
        final result = await deployer.validatePrerequisites();

        // Docker may or may not be installed; just verify we get a result.
        expect(result.message, isNotEmpty);
        expect(result.message.toLowerCase(), contains('docker'));
      });

      test('aws validation checks aws cli', () async {
        const config = DeployConfig(target: DeployTarget.aws);
        const deployer = Deployer(config);
        final result = await deployer.validatePrerequisites();

        expect(result.message, isNotEmpty);
        expect(result.message.toLowerCase(), contains('aws'));
      });

      test('azure validation checks az cli', () async {
        const config = DeployConfig(target: DeployTarget.azure);
        const deployer = Deployer(config);
        final result = await deployer.validatePrerequisites();

        expect(result.message, isNotEmpty);
        expect(result.message.toLowerCase(), contains('azure'));
      });

      test('gcp validation checks gcloud', () async {
        const config = DeployConfig(target: DeployTarget.gcp);
        const deployer = Deployer(config);
        final result = await deployer.validatePrerequisites();

        expect(result.message, isNotEmpty);
        // The message contains either 'gcp' or 'gcloud' or 'google'
        expect(
          result.message.toLowerCase(),
          anyOf(contains('gcp'), contains('gcloud'), contains('google')),
        );
      });
    });
  });
}
