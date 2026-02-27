# Troubleshooting

This page covers common issues encountered when building, running, and using the Lattice protocol, along with solutions.

## Build Errors

### `Could not find a file named "pubspec.yaml"`

**Cause:** Running `dart pub get` from the wrong directory.

**Solution:** Run from the workspace root:

```bash
cd lattice/
dart pub get
```

The workspace `pubspec.yaml` at the root resolves all sub-package dependencies.

### `The current Dart SDK version is X.Y.Z. Because lattice requires sdk >=3.7.0`

**Cause:** Your Dart SDK is too old.

**Solution:** Upgrade Dart to 3.7.0 or later:

```bash
# If using the standalone Dart SDK
brew upgrade dart    # macOS with Homebrew
# OR download from https://dart.dev/get-dart

# Verify
dart --version
```

### `Error: Couldn't resolve the package 'lattice_crypto'`

**Cause:** Dependencies not resolved.

**Solution:**

```bash
cd lattice/
dart pub get
```

If that fails, try clearing the cache:

```bash
dart pub cache clean
dart pub get
```

### `Error compiling to executable: ... compilation failed`

**Cause:** Compilation errors in the server binary.

**Solution:** First run the analyzer to identify issues:

```bash
dart analyze packages/lattice_server
```

Fix any reported issues, then retry compilation:

```bash
dart compile exe packages/lattice_server/bin/server.dart -o server
```

## Server Connection Issues

### `SocketException: Connection refused`

**Cause:** The server is not running, or it is bound to a different host/port.

**Solution:**

1. Verify the server is running:
   ```bash
   curl http://localhost:8080/api/v1/health
   ```

2. Check the host and port. If the server was started with `--host 0.0.0.0`, clients should connect to `localhost` or the machine's IP address.

3. If running in Docker, ensure the port mapping is correct:
   ```bash
   docker run -p 8080:8080 lattice-server --host 0.0.0.0
   ```
   The `--host 0.0.0.0` flag is required inside Docker to accept external connections.

### `LatticeApiException(409): User "alice" already registered`

**Cause:** Attempting to register a user ID that already exists.

**Solution:** Each user ID can only be registered once. If using in-memory storage, restart the server to clear all data. If using file storage, delete the `users.json` file or use a different user ID.

### `LatticeApiException(404): No pre-key bundle for user "alice"`

**Cause:** The user has not uploaded a pre-key, or the pre-key has already been consumed.

**Solution:** Upload a fresh pre-key:

```dart
await alice.uploadPreKey();
```

Pre-keys are one-time use. The server removes the pre-key after it is fetched.

### `LatticeApiException(429): Rate limit exceeded`

**Cause:** Too many requests from the same IP address within the rate limit window.

**Solution:** Wait for the rate limit window to reset (default: 1 minute), then retry. If testing, you can disable rate limiting by removing the `rateLimit` middleware from the server pipeline.

## Key Mismatch Errors

### `StateError: Session finalization failed: invalid signature from responder`

**Cause:** The session finalization on Alice's side detected that Bob's signature does not verify. Possible reasons:

1. **Mismatched keys:** Bob's public key on the server does not match the key he used to sign.
2. **Tampered message:** The key-exchange message was modified in transit.
3. **Wrong seed:** The randomness extractor seed was not transmitted correctly.
4. **Different security levels:** Alice and Bob are using different `SecurityLevel` settings.

**Solution:**

- Ensure both clients use the same `CryptoProvider` configuration (same `SecurityLevel`).
- Verify TLS is enabled to prevent message tampering.
- Re-register both users and retry the handshake from scratch.

### `StateError: Session creation failed: invalid pre-key signature`

**Cause:** Bob (the responder) could not verify Alice's signature on her ephemeral pre-key. The pre-key bundle may have been corrupted or Alice's public key on the server does not match.

**Solution:**

- Re-register Alice and upload a fresh pre-key.
- Ensure the server is returning the correct pre-key bundle for the requested user.

### Session keys do not match

**Cause:** Alice and Bob completed the handshake but derived different session keys.

**Solution:** This should not happen if both sides complete without errors. Debug by:

1. Verifying both sides use the same `SecurityLevel`.
2. Checking that the seed is correctly encoded and decoded in the session payload.
3. Running the integration tests:
   ```bash
   dart test packages/lattice_client/test/
   ```

## Performance Tuning

### Slow key generation

**Cause:** The pure-Dart implementations of ML-KEM and ML-DSA are slower than native implementations.

**Solution:**

- For development, the pure-Dart implementations are sufficient.
- For production, use FFI bindings to native PQC libraries (when available). Update `CryptoProvider` to return native implementations.
- Key generation can be moved to a background isolate:
  ```dart
  final result = await Isolate.run(() {
    return Registration(CryptoProvider()).generate();
  });
  ```

### Server handling many concurrent connections

**Cause:** The default shelf server is single-threaded.

**Solution:**

- For higher throughput, run multiple server instances behind a load balancer.
- Use `HttpServer.bind` with `shared: true` to allow multiple Dart isolates to accept connections on the same port.
- Ensure you are using a shared storage backend (not InMemoryStorage) for multi-instance deployments.

### Large pre-key bundles

**Cause:** Post-quantum key sizes are larger than classical equivalents. At L192, a pre-key bundle is approximately 6 KB.

**Solution:**

- This is inherent to lattice-based cryptography. Use L128 (NIST Level 1) if size is critical, at the cost of lower security margin.
- Enable HTTP compression (gzip) on the reverse proxy.

## Debug Logging

### Enable verbose server logging

The server logs all requests by default. To see more detail, run the server directly (not as a compiled binary) and inspect the output:

```bash
dart run packages/lattice_server/bin/server.dart 2>&1 | tee server.log
```

### Client-side debugging

Add logging around client operations:

```dart
try {
  await client.register();
  print('Registration successful');
} catch (e) {
  print('Registration failed: $e');
}

try {
  await client.uploadPreKey();
  print('Pre-key uploaded');
} catch (e) {
  print('Pre-key upload failed: $e');
}
```

### Network debugging

Use `curl` to manually test server endpoints:

```bash
# Health check
curl -s http://localhost:8080/api/v1/health | dart run tool/format_json.dart

# Register a test user
curl -X POST http://localhost:8080/api/v1/register \
  -H "Content-Type: application/json" \
  -d '{"userId": "test", "publicKey": "dGVzdA=="}'

# Check metrics
curl -s http://localhost:8080/api/v1/metrics
```

## Test Failures

### Running tests

```bash
# All packages
dart test

# Specific package
dart test packages/lattice_crypto/test/
dart test packages/lattice_protocol/test/
dart test packages/lattice_server/test/
dart test packages/lattice_client/test/
```

### Common test issues

- **Port conflicts:** Integration tests may start a server on port 8080. Ensure no other service is using that port.
- **Flaky tests:** If tests fail intermittently, check for timing-dependent assertions or port reuse issues.
- **Out of memory:** Post-quantum key generation is memory-intensive. Ensure at least 512 MB of RAM is available for tests.
