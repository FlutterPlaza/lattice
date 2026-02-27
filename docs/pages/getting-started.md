# Getting Started

Lattice is a post-quantum Signal protocol implementation in Dart/Flutter. It replaces Signal's X3DH key agreement with a construction based on lattice-based cryptography, providing security against both classical and quantum adversaries.

The protocol implements the SC-AKE (Strongly Compromised Authenticated Key Exchange) and SC-DAKE (Deniable variant) handshake protocols from:

> Hashimoto, K., Katsumata, S., Kwiatkowski, K., & Prest, T. (2022). "An Efficient and Generic Construction for Signal's Handshake (X3DH): Post-Quantum, State Leakage Secure, and Deniable." *Post-Quantum Cryptography (PQC 2022)*, Springer.

## Prerequisites

- **Dart SDK** 3.7.0 or later
- **Git** for cloning the repository
- **Docker** (optional, for containerized server deployment)

Verify your Dart installation:

```bash
dart --version
# Dart SDK version: 3.7.0 (or later)
```

## Installation

Clone the repository and install dependencies:

```bash
git clone https://github.com/flutterplaza/lattice.git
cd lattice
dart pub get
```

## Quick Start

### 1. Start the server

```bash
dart run packages/lattice_server/bin/server.dart
# Lattice server listening on localhost:8080
```

### 2. Run the tests

```bash
dart test
```

This runs tests across all packages: `lattice_crypto`, `lattice_protocol`, `lattice_server`, and `lattice_client`.

### 3. Establish a session (programmatic example)

```dart
import 'package:lattice_client/lattice_client.dart';

// Create clients for Alice and Bob
final alice = LatticeClient(
  userId: 'alice',
  connection: Connection(baseUrl: 'http://localhost:8080'),
);
final bob = LatticeClient(
  userId: 'bob',
  connection: Connection(baseUrl: 'http://localhost:8080'),
);

// Register both users
await alice.register();
await bob.register();

// Alice uploads a pre-key
await alice.uploadPreKey();

// Bob initiates a session with Alice
final bobSession = await bob.initiateSession('alice');

// Alice finalizes the session
final aliceSessions = await alice.respondToSessions();

// Both now share the same session key
assert(bobSession.sessionKey == aliceSessions.first.sessionKey);
```

## Project Structure

```
lattice/
  packages/
    lattice_crypto/     Core cryptographic primitives (KEM, SIG, PRF, Ext)
    lattice_protocol/   SC-AKE + SC-DAKE protocol logic
    lattice_server/     Key distribution server (shelf-based HTTP)
    lattice_client/     Client SDK for Dart/Flutter applications
  tools/
    deploy/             Interactive deployment CLI (AWS/Azure/GCP/local)
    monitor/            Server health monitoring tool
    ring_deploy/        Ring protocol deployment tooling
  docs/                 This documentation site
```

### Package Dependency Graph

```
lattice_client
  -> lattice_protocol
       -> lattice_crypto
  -> lattice_server (dev only, for integration tests)
```

- **lattice_crypto** has no dependencies on other Lattice packages. It provides abstract interfaces (`Kem`, `Sig`, `RingSig`, `Prf`, `Ext`) and pure-Dart reference implementations.
- **lattice_protocol** depends on `lattice_crypto` and contains the protocol state machines (`Initiator`, `Responder`, `Registration`) and data types (`SessionId`, `PreKeyBundle`, `KeyExchangeMessage`).
- **lattice_server** is a standalone HTTP server that stores and serves public keys, pre-key bundles, and pending key exchange messages.
- **lattice_client** ties everything together, providing a high-level `LatticeClient` API.

## Next Steps

- [Protocol Specification](#protocol) -- Understand the SC-AKE handshake in detail
- [Server Setup](#server) -- Configure and run the key distribution server
- [Client Usage](#client) -- Integrate Lattice into your Dart/Flutter application
- [Deployment Guide](#deployment) -- Deploy to Docker, AWS, Azure, GCP, or Firebase
- [Platform Integrations](#platforms) -- Firebase, Serverpod, and Supabase adapters
- [Security](#security) -- Review the security model and best practices
