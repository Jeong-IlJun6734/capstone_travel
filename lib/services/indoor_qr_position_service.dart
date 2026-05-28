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

  static const _host = '192.168.0.13';
  static const _port = 8000;

  final http.Client _client;

  Future<IndoorQrPosition> resolveQrPosition(String qrValue) async {
    final qrId = _qrIdFromValue(qrValue);
    final response = await _client.get(
      Uri(
        scheme: 'http',
        host: _host,
        port: _port,
        pathSegments: ['api', 'station', 'qr_verify', qrId],
      ),
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

    try {
      final decoded = jsonDecode(trimmed);
      final payload = _asMap(decoded);
      final qrId = payload['qr_id'] ?? payload['qrId'];
      if (qrId is String && qrId.isNotEmpty) {
        return qrId;
      }
    } catch (_) {
      // Non-JSON QR payloads are handled below.
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final queryQrId =
          uri.queryParameters['qr_id'] ?? uri.queryParameters['qrId'];
      if (queryQrId != null && queryQrId.isNotEmpty) {
        return queryQrId;
      }

      if (uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }
    }

    return trimmed;
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
