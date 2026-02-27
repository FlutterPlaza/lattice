import 'dart:typed_data';

import 'package:lattice_protocol/src/key_types.dart';

/// An established session state after a successful SC-AKE handshake.
///
/// Holds the session key, session identifier, and peer identity information.
class Session {
  /// Creates a [Session] with the given parameters.
  ///
  /// If [createdAt] is not provided, it defaults to [DateTime.now].
  Session({
    required this.sessionId,
    required this.sessionKey,
    required this.localIdentity,
    required this.remoteIdentity,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// The session identifier `sid`.
  final SessionId sessionId;

  /// The derived session key (shared between both parties).
  final Uint8List sessionKey;

  /// The local user's identity string.
  final String localIdentity;

  /// The remote peer's identity string.
  final String remoteIdentity;

  /// The time at which this session was established.
  final DateTime createdAt;
}
