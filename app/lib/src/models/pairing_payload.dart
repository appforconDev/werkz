import 'dart:convert';

// The base64url payload encoded in the pairing QR (event-model.md §0 / daemon
// pairing/auth.ts): { v, host, port, token }.
class PairingPayload {
  final String host;
  final int port;
  final String token;

  const PairingPayload({required this.host, required this.port, required this.token});

  static PairingPayload? tryDecode(String raw) {
    try {
      final s = raw.trim();
      final normalized = s.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized.padRight((normalized.length + 3) & ~3, '=');
      final json = jsonDecode(utf8.decode(base64.decode(padded))) as Map<String, dynamic>;
      if (json['host'] == null || json['port'] == null || json['token'] == null) return null;
      return PairingPayload(
        host: json['host'] as String,
        port: (json['port'] as num).toInt(),
        token: json['token'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  // Manual entry fallback: "host:port" (token fetched separately not supported;
  // used only when the QR payload is pasted whole, handled by tryDecode).
  static PairingPayload? fromHostPort(String hostPort, String token) {
    final parts = hostPort.split(':');
    if (parts.length != 2) return null;
    final port = int.tryParse(parts[1]);
    if (port == null) return null;
    return PairingPayload(host: parts[0], port: port, token: token);
  }

  String get httpBase => 'http://$host:$port';
  String wsUrl(String sessionToken) => 'ws://$host:$port/ws?token=$sessionToken';
}
