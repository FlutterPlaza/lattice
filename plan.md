# Lattice: Post-Quantum Signal Protocol Implementation Plan

A complete implementation of the post-quantum Signal handshake protocol based on
"An Efficient and Generic Construction for Signal's Handshake (X3DH):
Post-Quantum, State Leakage Secure, and Deniable" (Hashimoto et al., PQC 2022).

---

## Phase 0: Repository Scaffolding

- [x] Create Dart workspace root (`pubspec.yaml` with `workspace:` key)
- [x] Create `packages/lattice_crypto/` package skeleton
- [x] Create `packages/lattice_protocol/` package skeleton
- [x] Create `packages/lattice_server/` package skeleton
- [x] Create `packages/lattice_client/` package skeleton
- [x] Create `tools/deploy/` package skeleton
- [x] Create `tools/monitor/` package skeleton
- [x] Add shared `analysis_options.yaml` with strict linting
- [x] Add `melos.yaml` for workspace scripts (analyze, format, test)
- [x] Add `LICENSE` (MIT), `README.md`, `CONTRIBUTORS.md`

## Phase 1: Core Cryptographic Primitives (`lattice_crypto`)

- [x] Define `SecurityLevel` enum (`l128`, `l192`, `l256`) with ML-KEM / ML-DSA parameter sizes
- [x] Define abstract `Kem` interface (`keyGen`, `encap`, `decap`)
- [x] Define abstract `Sig` interface (`keyGen`, `sign`, `verify`)
- [x] Define abstract `RingSig` interface (`keyGen`, `sign`, `verify`)
- [x] Implement `Prf` (PRF with counter-mode extension using HMAC-SHA-256)
- [x] Implement `Ext` (strong randomness extractor using HKDF-SHA-256)
- [x] Implement `KemPure` (pure-Dart development KEM using HMAC-based simulation)
- [x] Implement `SigPure` (pure-Dart development SIG using HMAC-based simulation)
- [x] Implement `RingSigPure` (pure-Dart development ring signature using HMAC-based simulation)
- [x] Implement `CryptoProvider` factory class for instantiating primitives at a given security level
- [x] Create barrel file (`lattice_crypto.dart`) exporting all public APIs
- [x] Write unit tests for all primitives (KEM round-trip, SIG sign/verify, PRF determinism, Ext extraction)

## Phase 2: Protocol Implementation (`lattice_protocol`)

- [x] Define `LongTermPublicKey` (`ek`, `vk`) and `LongTermSecretKey` (`dk`, `sk`) key types
- [x] Define `EphemeralPreKey` (`ekT`, `dkT`, `sigma`) type
- [x] Define `SessionId` (length-prefixed concatenation: `A || B || lpkA || lpkB || ekT || C || CT`)
- [x] Define `PreKeyBundle` message type with `serialize` / `deserialize`
- [x] Define `KeyExchangeMessage` message type with `serialize` / `deserialize`
- [x] Implement `Serialization` helpers (length-prefixed binary encoding)
- [x] Implement `Registration.generate()` (KEM.KeyGen + SIG.KeyGen)
- [x] Implement `Initiator.uploadPreKey()` (wKEM.KeyGen + SIG.Sign)
- [x] Implement `Initiator.finalizeSession()` (Decap, Ext, PRF, verify signature)
- [x] Implement `Responder.createSession()` (verify pre-key, Encap, Ext, PRF, sign, encrypt)
- [x] Implement `Session` state class holding session key, session ID, and peer identities
- [x] Define abstract `IdentityStore`, `PreKeyStore`, `SessionStore` interfaces
- [x] Implement `InMemoryIdentityStore`, `InMemoryPreKeyStore`, `InMemorySessionStore`
- [x] Create barrel file (`lattice_protocol.dart`) exporting all public APIs
- [x] Write unit tests for registration, handshake, serialization round-trips, and tamper detection

## Phase 3: Signal Server (`lattice_server`)

- [x] Define `Storage` abstract interface (users, pre-keys, messages, stats)
- [x] Implement `InMemoryStorage` backend for development and testing
- [x] Implement `FileStorage` backend for persistent JSON-file storage
- [x] Define `UserRecord`, `PreKeyRecord`, `MessageRecord` data classes with JSON serialization
- [x] Implement `Routes` with Shelf router:
  - [x] `POST /api/v1/register` -- user registration
  - [x] `POST /api/v1/prekeys` -- upload pre-key bundle
  - [x] `GET /api/v1/prekeys/<userId>` -- fetch and consume pre-key bundle
  - [x] `POST /api/v1/messages/<userId>` -- send key-exchange message
  - [x] `GET /api/v1/messages/<userId>` -- fetch and clear pending messages
  - [x] `GET /api/v1/health` -- health check endpoint
  - [x] `GET /api/v1/metrics` -- operational metrics
- [x] Implement middleware pipeline (logging, auth, rate limiting, CORS, error handling)
- [x] Implement `LatticeServer` class (configurable host/port, storage, middleware, graceful shutdown)
- [x] Create `bin/server.dart` CLI entry point with `args` package
- [x] Create `Dockerfile` for containerized deployment
- [x] Write unit tests for storage backends, routes, and middleware

## Phase 4: Flutter Client SDK (`lattice_client`)

- [x] Implement `LatticeConnection` (HTTP client wrapper for server communication)
- [x] Implement `SecureStorage` abstraction for persisting keys and sessions
- [x] Implement `SessionManager` for managing multiple concurrent sessions
- [x] Implement `LatticeClient` facade combining connection, storage, and session management
- [x] Create barrel file (`lattice_client.dart`) exporting all public APIs
- [x] Write unit tests for client components

## Phase 5: Deployment Script (`tools/deploy`)

- [x] Define `DeployTarget` enum (`local`, `aws`, `azure`, `gcp`)
- [x] Implement `DeployConfig` with YAML save/load and `fromMap`/`toMap`
- [x] Implement `ScalingConfig` for auto-scaling parameters
- [x] Implement `Deployer` with `validatePrerequisites`, `deploy`, `healthCheck`, `teardown`
- [x] Support dry-run mode for safe deployment planning
- [x] Generate cloud-specific deployment commands (ECS, Container Apps, Cloud Run)
- [x] Write unit tests for config serialization and deployer logic

## Phase 6: Monitoring Script (`tools/monitor`)

- [x] Implement `HealthChecker` with HTTP-based health checks, history tracking, uptime percentage
- [x] Implement `MetricsCollector` for periodic server metrics collection
- [x] Implement `AlertManager` with configurable thresholds and severity levels
- [x] Define `HealthStatus`, `MetricsSnapshot`, `Alert`, `AlertThreshold` data classes
- [x] Support pluggable `http.Client` for testing (MockClient)
- [x] Write unit tests for health checking, metrics collection, and alert evaluation

## Phase 7: Documentation Website (`docs/`)

- [x] Create documentation site structure
- [x] Write protocol overview and architecture documentation
- [x] Write API reference documentation
- [x] Write getting-started guide
- [x] Write deployment guide

## Phase 8: CI/CD Pipelines

- [x] Create GitHub Actions workflow for CI (analyze, format, test)
- [x] Create GitHub Actions workflow for publishing
- [x] Configure Melos scripts for workspace-wide operations
- [x] Add code coverage reporting

## Phase 9: Final Integration and Hardening

- [x] Create end-to-end integration test (`test/integration_test.dart`) covering:
  - [x] Full SC-AKE handshake at all three security levels (l128, l192, l256)
  - [x] Session key agreement verification (kA == kB)
  - [x] Session ID matching between initiator and responder
  - [x] Tampered message detection (ciphertext, ephemeral ciphertext, encrypted signature)
  - [x] Invalid pre-key signature rejection
  - [x] Concurrent sessions between multiple user pairs with unique keys
  - [x] Serialization round-trips for all message types (LongTermPublicKey, PreKeyBundle, KeyExchangeMessage)
  - [x] Server storage operations (InMemoryStorage CRUD for users, pre-keys, messages)
  - [x] End-to-end flow through server storage (register, upload, fetch, handshake)
  - [x] Monitoring components (HealthChecker, AlertManager, MetricsCollector with mock HTTP)
  - [x] Deployment config save/load round-trip and Deployer dry-run
  - [x] Protocol store abstractions (InMemoryIdentityStore, InMemoryPreKeyStore, InMemorySessionStore)
  - [x] Crypto primitive sanity checks (KEM, SIG, PRF, Ext) at all security levels
- [x] Ensure `dart analyze` passes with zero issues across the entire workspace
- [x] Ensure `dart test` passes for all packages and integration tests
- [x] Create `plan.md` implementation checklist (this file)
