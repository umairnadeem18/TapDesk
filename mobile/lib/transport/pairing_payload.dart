import 'dart:convert';

/// Parsed and validated contents of a `tapdesk://pair` deep link.
///
/// The validation rules here are `docs/protocol.md` section 2.3, and they are
/// deliberately strict: a malformed payload sends the user to manual entry
/// rather than half-connecting, because a QR that scans but does not work is
/// far more confusing than one that is refused.
class PairingPayload {
  const PairingPayload({
    required this.version,
    required this.name,
    required this.ips,
    required this.port,
    required this.token,
    required this.fingerprint,
  });

  /// Protocol version. Only 1 exists.
  final int version;

  /// Display name of the PC.
  final String name;

  /// Candidate addresses, most likely first.
  final List<String> ips;

  final int port;

  /// One-time pairing token, base64url.
  final String token;

  /// SHA-256 of the PC certificate's DER bytes, lowercase hex, 64 chars.
  final String fingerprint;

  /// The fingerprint exactly as the PC writes it: base64url of the raw digest,
  /// with no separators. The protocol uses lowercase hex on the wire but
  /// base64url in the QR, because a QR encoder handles base64 far better than
  /// a 64-character hex string.
  String get wireFingerprint => fingerprint;

  /// Same payload in the manual-entry form, for the typed fallback.
  Map<String, dynamic> toManualJson(String pin) => {
        'v': version,
        'ip': ips.first,
        'port': port,
        'pin': pin,
        'fp': fingerprint,
      };

  /// Parse the `d=` query parameter of a `tapdesk://pair` deep link.
  ///
  /// Returns null for anything malformed rather than throwing: the caller
  /// shows manual entry, and an exception here would be a crash on a screen
  /// whose whole job is to be scanned at.
  static PairingPayload? tryParseDeepLink(String link) {
    const scheme = 'tapdesk://pair';
    if (!link.toLowerCase().startsWith(scheme)) return null;

    final queryStart = link.indexOf('?');
    if (queryStart == -1) return null;

    final query = link.substring(queryStart + 1);
    final data = _queryValue(query, 'd');
    if (data == null || data.isEmpty) return null;

    return tryParseBase64Payload(data);
  }

  /// Parse the base64url-encoded JSON body, as produced by the companion.
  static PairingPayload? tryParseBase64Payload(String encoded) {
    try {
      // base64url without padding.
      final padded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
      final json = utf8.decode(base64Url.decode(padded));
      return tryParseJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Validate a decoded payload against section 2.3 of the protocol.
  static PairingPayload? tryParseJson(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final version = decoded['v'];
    if (version is! int || version != 1) return null;

    final name = decoded['name'];
    if (name is! String || name.isEmpty || name.length > 32) return null;

    final ips = decoded['ips'];
    if (ips is! List || ips.isEmpty || ips.length > 4) return null;
    if (ips.any((ip) => ip is! String || !_looksLikeIpv4(ip))) return null;

    final port = decoded['port'];
    if (port is! int || port < 1024 || port > 65535) return null;

    final token = decoded['token'];
    if (token is! String || !_isBase64Url(token, 43)) return null;

    final fp = decoded['fp'];
    if (fp is! String || !_isFingerprint(fp)) return null;

    return PairingPayload(
      version: version,
      name: name,
      ips: ips.cast<String>(),
      port: port,
      token: token,
      fingerprint: fp,
    );
  }

  /// Parse the manual-entry form: `{ip, port, pin, fp}`.
  ///
  /// `pin` is a 6-digit numeric rendering of the same one-time token.
  static PairingPayload? tryParseManual({
    required String ip,
    required int port,
    required String pin,
    required String fingerprint,
  }) {
    if (!_looksLikeIpv4(ip)) return null;
    if (port < 1024 || port > 65535) return null;
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return null;
    if (!_isFingerprint(fingerprint)) return null;

    return PairingPayload(
      version: 1,
      name: 'Computer',
      ips: [ip],
      port: port,
      // The companion accepts the 6-digit PIN in place of the base64url token,
      // so it is carried through unchanged and validated there.
      token: pin,
      fingerprint: fingerprint,
    );
  }

  /// 32 random bytes, base64url, unpadded - so exactly 43 characters.
  static bool _isBase64Url(String value, int length) {
    if (value.length != length) return false;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
  }

  /// Lowercase hex, no separators, exactly 64 characters.
  ///
  /// Uppercase, `:`-separated and base64 forms are all rejected rather than
  /// normalised: a fingerprint that needs cleaning up is a fingerprint we
  /// should not trust to pin a certificate.
  static bool _isFingerprint(String value) {
    if (value.length != 64) return false;
    return RegExp(r'^[0-9a-f]+$').hasMatch(value);
  }

  /// Deliberately simple. Anything stricter belongs in the companion, which
  /// knows the real network topology.
  static bool _looksLikeIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
      if (part.length > 1 && part.startsWith('0')) return false;
    }
    return true;
  }

  static String? _queryValue(String query, String key) {
    for (final pair in query.split('&')) {
      final index = pair.indexOf('=');
      if (index == -1) continue;
      if (pair.substring(0, index) == key) return pair.substring(index + 1);
    }
    return null;
  }
}
