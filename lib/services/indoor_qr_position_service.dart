import 'dart:convert';

import 'package:http/http.dart' as http;

class IndoorQrPosition {
  const IndoorQrPosition({
    required this.qrValue,
    required this.x,
    required this.y,
    required this.resolvedAt,
    required this.payload,
  });

  final String qrValue;
  final double x;
  final double y;
  final DateTime resolvedAt;
  final Map<String, dynamic> payload;
}

class IndoorQrPositionService {
  IndoorQrPositionService({http.Client? client})
    : _client = client ?? http.Client();

  static final Uri _baseUri = Uri.parse(
    'https://stood-journalist-answers-procedures.trycloudflare.com',
  );

  final http.Client _client;

  Future<IndoorQrPosition> resolveQrPosition(String qrValue) async {
    final qrId = _qrIdFromValue(qrValue);
    final response = await _client.get(
      _baseUri.replace(pathSegments: ['api', 'station', 'qr_verify', qrId]),
      headers: const {'accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IndoorQrPositionException(
        'QR verification request failed (${response.statusCode})',
      );
    }

    final payload = _asMap(jsonDecode(utf8.decode(response.bodyBytes)));
    final (x, y) = _positionFromPayload(payload);
    return IndoorQrPosition(
      qrValue: qrValue,
      x: x,
      y: y,
      resolvedAt: DateTime.now(),
      payload: payload,
    );
  }

  String _qrIdFromValue(String qrValue) {
    final trimmed = qrValue.trim();

    final directQrId = _qrIdFromJsonLikeValue(trimmed);
    if (directQrId != null) {
      return directQrId;
    }

    final decodedValue = _tryDecodeUriComponent(trimmed);
    if (decodedValue != null && decodedValue != trimmed) {
      final decodedQrId = _qrIdFromJsonLikeValue(decodedValue);
      if (decodedQrId != null) {
        return decodedQrId;
      }
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final queryQrId =
          uri.queryParameters['qr_id'] ?? uri.queryParameters['qrId'];
      if (queryQrId != null && queryQrId.isNotEmpty) {
        return queryQrId.trim();
      }

      if (uri.pathSegments.isNotEmpty) {
        final pathQrId = _qrIdFromJsonLikeValue(uri.pathSegments.last);
        if (pathQrId != null) {
          return pathQrId;
        }

        final decodedPathSegment = _tryDecodeUriComponent(
          uri.pathSegments.last,
        );
        if (decodedPathSegment != null) {
          final decodedPathQrId = _qrIdFromJsonLikeValue(decodedPathSegment);
          if (decodedPathQrId != null) {
            return decodedPathQrId;
          }
        }
      }
    }

    final hexQrId = RegExp(
      r'\b[0-9a-fA-F]{64}\b',
    ).firstMatch(decodedValue ?? trimmed)?.group(0);
    if (hexQrId != null) {
      return hexQrId;
    }

    return trimmed;
  }

  String? _qrIdFromJsonLikeValue(String value) {
    final trimmed = value.trim();

    try {
      final decoded = jsonDecode(trimmed);
      final payload = _asMap(decoded);
      final qrId = payload['qr_id'] ?? payload['qrId'];
      if (qrId is String && qrId.trim().isNotEmpty) {
        return qrId.trim();
      }
    } catch (_) {
      // Non-JSON QR payloads are handled below.
    }

    final quotedQrId = RegExp(
      r'''["']qr_?id["']\s*:\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(trimmed)?.group(1);
    if (quotedQrId != null && quotedQrId.trim().isNotEmpty) {
      return quotedQrId.trim();
    }

    final hexQrId = RegExp(r'^[0-9a-fA-F]{64}$').firstMatch(trimmed)?.group(0);
    if (hexQrId != null) {
      return hexQrId;
    }

    return null;
  }

  String? _tryDecodeUriComponent(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return null;
    }
  }

  (double, double) _positionFromPayload(dynamic payload) {
    final map = _asMap(payload);
    if (map['valid'] == false) {
      throw const IndoorQrPositionException('QR verification failed.');
    }

    final directX = _readDouble(
      map['x'] ?? map['position_x'] ?? map['positionX'],
    );
    final directY = _readDouble(
      map['y'] ?? map['position_y'] ?? map['positionY'],
    );
    if (directX != null && directY != null) {
      return (directX, directY);
    }

    final position = _asMap(map['position'] ?? map['coordinate']);
    final nestedX = _readDouble(
      position['x'] ?? position['position_x'] ?? position['positionX'],
    );
    final nestedY = _readDouble(
      position['y'] ?? position['position_y'] ?? position['positionY'],
    );
    if (nestedX != null && nestedY != null) {
      return (nestedX, nestedY);
    }

    final imageXy = _asList(map['image_xy'] ?? map['imageXy'] ?? map['xy']);
    if (imageXy.length >= 2) {
      final imageX = _readDouble(imageXy[0]);
      final imageY = _readDouble(imageXy[1]);
      if (imageX != null && imageY != null) {
        return (imageX, imageY);
      }
    }

    throw const IndoorQrPositionException(
      'QR verification response has no indoor position.',
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  List<dynamic> _asList(dynamic value) {
    return value is List ? value : const [];
  }

  double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}

class IndoorQrPositionException implements Exception {
  const IndoorQrPositionException(this.message);

  final String message;

  @override
  String toString() => message;
}
