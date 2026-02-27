import 'package:lattice_protocol/lattice_protocol.dart';

/// Manages active protocol sessions established via SC-AKE handshakes.
///
/// Sessions are indexed by the remote peer's identity string.
class SessionManager {
  final Map<String, Session> _sessions = <String, Session>{};

  /// Stores a [session] for the given [peerId].
  ///
  /// If a session already exists for [peerId] it is replaced.
  void addSession(String peerId, Session session) {
    _sessions[peerId] = session;
  }

  /// Returns the session for [peerId], or `null` if none exists.
  Session? getSession(String peerId) => _sessions[peerId];

  /// Returns an unmodifiable list of all active sessions.
  List<Session> get activeSessions =>
      List<Session>.unmodifiable(_sessions.values);

  /// Removes the session for [peerId].
  void removeSession(String peerId) {
    _sessions.remove(peerId);
  }

  /// Whether a session exists for [peerId].
  bool hasSession(String peerId) => _sessions.containsKey(peerId);

  /// The number of active sessions.
  int get sessionCount => _sessions.length;
}
