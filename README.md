# Lattice

[![CI](https://github.com/flutterplaza/lattice/actions/workflows/ci.yml/badge.svg)](https://github.com/flutterplaza/lattice/actions/workflows/ci.yml)
[![License: BSD 3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-3.7+-0175C2.svg)](https://dart.dev)

Post-quantum Signal protocol implementation in Dart/Flutter.

Implements the SC-AKE and SC-DAKE handshake protocols from ["An Efficient and Generic Construction for Signal's Handshake (X3DH): Post-Quantum, State Leakage Secure, and Deniable"](https://doi.org/10.1007/978-3-031-17234-2_2) (Hashimoto et al., PQC 2022).

## Overview

Lattice replaces Signal's X3DH key agreement with a post-quantum construction based on:
- **ML-KEM** (Kyber) for key encapsulation (NIST FIPS 203)
- **ML-DSA** (Dilithium) for digital signatures (NIST FIPS 204)
- **HMAC-SHA256** for PRF and randomness extraction

### Security Levels

| Level | KEM | SIG | Security |
|-------|-----|-----|----------|
| L128 | ML-KEM-512 | ML-DSA-44 | 128-bit post-quantum |
| L192 | ML-KEM-768 | ML-DSA-65 | 192-bit post-quantum |
| L256 | ML-KEM-1024 | ML-DSA-87 | 256-bit post-quantum |

## Packages

### Core

| Package | Description |
|---------|-------------|
| [lattice_crypto](packages/lattice_crypto/) | Cryptographic primitives (KEM, SIG, PRF, Ext) |
| [lattice_protocol](packages/lattice_protocol/) | SC-AKE + SC-DAKE protocol logic |
| [lattice_server](packages/lattice_server/) | Key distribution server (Shelf) |
| [lattice_client](packages/lattice_client/) | Flutter/Dart client SDK |

### Platform Integrations

| Package | Description |
|---------|-------------|
| [lattice_server_firebase](packages/lattice_server_firebase/) | Firebase Cloud Run + Firestore storage |
| [lattice_server_serverpod](packages/lattice_server_serverpod/) | Serverpod endpoints + PostgreSQL storage |
| [lattice_server_supabase](packages/lattice_server_supabase/) | Supabase PostgreSQL storage adapter |

### Tools

| Tool | Description |
|------|-------------|
| [deploy](tools/deploy/) | Interactive deployment CLI (Docker/AWS/Azure/GCP/Firebase) |
| [monitor](tools/monitor/) | Server health monitoring and alerting |

## Quick Start

```bash
# Clone and install
git clone https://github.com/flutterplaza/lattice.git
cd lattice
dart pub get

# Run all tests
dart test

# Start the server
dart run packages/lattice_server/bin/server.dart
```

### Establish a Session

```dart
import 'package:lattice_client/lattice_client.dart';

final alice = LatticeClient(
  userId: 'alice',
  connection: Connection(baseUrl: 'http://localhost:8080'),
);
final bob = LatticeClient(
  userId: 'bob',
  connection: Connection(baseUrl: 'http://localhost:8080'),
);

await alice.register();
await bob.register();
await alice.uploadPreKey();

final bobSession = await bob.initiateSession('alice');
final aliceSessions = await alice.respondToSessions();
// Both share the same post-quantum session key
```

## Deployment Options

| Platform | Method | Storage Backend |
|----------|--------|----------------|
| Local | Docker | In-memory / File |
| AWS ECS | Docker + ECR | File / External DB |
| Azure Container Apps | Docker + ACR | File / External DB |
| GCP Cloud Run | Docker + GCR | File / External DB |
| Firebase | Cloud Run + Hosting | Firestore |
| Serverpod | Native Dart server | PostgreSQL |
| Supabase | External server | Supabase PostgreSQL |

```bash
# Deploy locally with Docker
dart run tools/deploy/bin/deploy.dart deploy --target local

# Deploy to Firebase Cloud Run
dart run tools/deploy/bin/deploy.dart deploy --target firebase

# Deploy to GCP Cloud Run
dart run tools/deploy/bin/deploy.dart deploy --target gcp
```

## Documentation

Full documentation is available at the [documentation website](https://flutterplaza.github.io/lattice/) or in the [docs/](docs/) directory.

- [Getting Started](docs/pages/getting-started.md)
- [Protocol Specification](docs/pages/protocol.md)
- [Server Setup](docs/pages/server.md)
- [Deployment Guide](docs/pages/deployment.md)
- [Platform Integrations](docs/pages/platforms.md)
- [Security Model](docs/pages/security.md)
- [API Reference](docs/pages/api-reference.md)

## Publishing

Packages are published to pub.dev via tag-triggered CI:

```bash
git tag v0.1.0
git push origin v0.1.0
```

This triggers the `publish.yml` workflow which publishes `lattice_crypto` to pub.dev using OIDC authentication.

## Security

This implementation targets post-quantum security against both passive and active adversaries:

- **SC-AKE**: Authenticated key exchange with state leakage security
- **SC-DAKE**: Deniable authenticated key exchange using ring signatures
- No cryptographic material is ever logged
- Constant-time comparisons for security-critical operations
- TLS enforcement for production deployments

## License

BSD 3-Clause License. See [LICENSE](LICENSE).

## Citation

```bibtex
@inproceedings{hashimoto2022efficient,
  title={An Efficient and Generic Construction for Signal's Handshake (X3DH): Post-Quantum, State Leakage Secure, and Deniable},
  author={Hashimoto, Keitaro and Katsumata, Shuichi and Kwiatkowski, Kris and Prest, Thomas},
  booktitle={Post-Quantum Cryptography},
  year={2022},
  publisher={Springer}
}
```

## Contributing

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for paper authors and project contributors.
