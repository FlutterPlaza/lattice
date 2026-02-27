import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;

/// Server middleware for the Lattice key distribution server.
///
/// Provides logging, authentication, rate limiting, CORS, and error handling.
class Middleware {
  /// Logging middleware that logs method, path, status code, and duration.
  ///
  /// CRITICAL: Never logs request or response bodies, as they may contain
  /// cryptographic material.
  static shelf.Middleware logging() => (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      final stopwatch = Stopwatch()..start();
      final method = request.method;
      final path = request.requestedUri.path;

      shelf.Response response;
      try {
        response = await innerHandler(request);
      } catch (e) {
        stopwatch.stop();
        // ignore: avoid_print
        print(
          '${DateTime.now().toIso8601String()} '
          '$method $path -> 500 '
          '(${stopwatch.elapsedMilliseconds}ms)',
        );
        rethrow;
      }

      stopwatch.stop();
      // ignore: avoid_print
      print(
        '${DateTime.now().toIso8601String()} '
        '$method $path -> ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      return response;
    };
  };

  /// Auth token middleware that checks for a Bearer token in the
  /// Authorization header.
  ///
  /// For now this is a placeholder that accepts any non-empty Bearer token.
  /// In production, replace with real token validation.
  static shelf.Middleware authToken() => (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      // Allow health and metrics endpoints without auth.
      final path = request.requestedUri.path;
      if (path.endsWith('/health') || path.endsWith('/metrics')) {
        return innerHandler(request);
      }

      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return shelf.Response(
          401,
          body: jsonEncode({
            'error': 'Missing or invalid Authorization header',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final token = authHeader.substring('Bearer '.length).trim();
      if (token.isEmpty) {
        return shelf.Response(
          401,
          body: jsonEncode({'error': 'Empty bearer token'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Placeholder: accept any non-empty token.
      return innerHandler(request);
    };
  };

  /// Simple in-memory per-IP rate limiting middleware.
  ///
  /// Allows at most [maxRequests] requests per [window] per client IP.
  static shelf.Middleware rateLimit({
    int maxRequests = 100,
    Duration window = const Duration(minutes: 1),
  }) {
    final buckets = <String, _RateBucket>{};

    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        // Use X-Forwarded-For if present, otherwise fall back to
        // connection info or a default.
        final ip =
            request.headers['x-forwarded-for']?.split(',').first.trim() ??
            'unknown';

        final now = DateTime.now();
        final bucket = buckets.putIfAbsent(ip, () => _RateBucket(now));

        // Reset window if expired.
        if (now.difference(bucket.windowStart) > window) {
          bucket
            ..windowStart = now
            ..count = 0;
        }

        bucket.count++;

        if (bucket.count > maxRequests) {
          return shelf.Response(
            429,
            body: jsonEncode({'error': 'Rate limit exceeded'}),
            headers: {'content-type': 'application/json'},
          );
        }

        return innerHandler(request);
      };
    };
  }

  /// CORS middleware that allows cross-origin client access.
  static shelf.Middleware cors() => (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      // Handle CORS preflight requests.
      if (request.method == 'OPTIONS') {
        return shelf.Response.ok('', headers: _corsHeaders);
      }

      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders);
    };
  };

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
    'Access-Control-Max-Age': '86400',
  };

  /// Error-handling middleware that catches exceptions and returns proper
  /// JSON error responses.
  static shelf.Middleware errorHandler() => (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      try {
        return await innerHandler(request);
      } on FormatException catch (e) {
        return shelf.Response(
          400,
          body: jsonEncode({'error': 'Bad request: ${e.message}'}),
          headers: {'content-type': 'application/json'},
        );
      } on StateError catch (e) {
        return shelf.Response(
          409,
          body: jsonEncode({'error': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        // Do NOT include exception details in production -- they may leak
        // internal state. Log the error server-side instead.
        // ignore: avoid_print
        print('Unhandled error: $e');
        return shelf.Response.internalServerError(
          body: jsonEncode({'error': 'Internal server error'}),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  };
}

/// Internal rate-limit bucket for a single IP address.
class _RateBucket {
  _RateBucket(this.windowStart);

  DateTime windowStart;
  int count = 0;
}
