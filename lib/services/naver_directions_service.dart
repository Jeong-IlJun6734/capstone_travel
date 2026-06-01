import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _naverDirectionClientIdAssetPath = 'server/NAVER_DIRECTION_CLIENT_ID.txt';
const _naverDirectionClientSecretAssetPath =
    'server/NAVER_DIRECTION_CLIENT_SECRET.txt';
const _naverDirectionClientId = String.fromEnvironment(
  'NAVER_DIRECTION_CLIENT_ID',
);
const _naverDirectionClientSecret = String.fromEnvironment(
  'NAVER_DIRECTION_CLIENT_SECRET',
);

String _cleanCredential(String value) {
  return value
      .replaceAll('\uFEFF', '')
      .replaceAll('\u200B', '')
      .replaceAll('\u200C', '')
      .replaceAll('\u200D', '')
      .trim();
}

class NaverDirectionCredentialsLoader {
  const NaverDirectionCredentialsLoader();

  Future<NaverDirectionCredentials> load() async {
    final envCredentials = NaverDirectionCredentials(
      clientId: _cleanCredential(_naverDirectionClientId),
      clientSecret: _cleanCredential(_naverDirectionClientSecret),
    );
    if (envCredentials.isReady) {
      return envCredentials;
    }

    try {
      final values = await Future.wait([
        rootBundle.loadString(_naverDirectionClientIdAssetPath),
        rootBundle.loadString(_naverDirectionClientSecretAssetPath),
      ]);
      return NaverDirectionCredentials(
        clientId: _cleanCredential(values[0]),
        clientSecret: _cleanCredential(values[1]),
      );
    } catch (_) {
      return const NaverDirectionCredentials(clientId: '', clientSecret: '');
    }
  }
}

class NaverDirectionsService {
  const NaverDirectionsService({
    http.Client? client,
    NaverDirectionCredentialsLoader credentialsLoader =
        const NaverDirectionCredentialsLoader(),
  }) : _client = client,
       _credentialsLoader = credentialsLoader;

  final http.Client? _client;
  final NaverDirectionCredentialsLoader _credentialsLoader;

  Future<NaverDirectionSummary> drivingSummary({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) async {
    final credentials = await _credentialsLoader.load();
    if (!credentials.isReady) {
      throw const NaverDirectionsException(
        'Naver Directions API key and secret are required.',
      );
    }

    final uri =
        Uri.https('maps.apigw.ntruss.com', '/map-direction/v1/driving', {
          'start': '$startLongitude,$startLatitude',
          'goal': '$endLongitude,$endLatitude',
          'option': 'trafast',
        });

    final ownsClient = _client == null;
    final client = _client ?? http.Client();

    try {
      final response = await client.get(
        uri,
        headers: {
          'x-ncp-apigw-api-key-id': credentials.clientId,
          'x-ncp-apigw-api-key': credentials.clientSecret,
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NaverDirectionsException(
          'Naver Directions request failed: HTTP ${response.statusCode} ${utf8.decode(response.bodyBytes)}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const NaverDirectionsException(
          'Naver Directions response format is invalid.',
        );
      }

      final route = decoded['route'];
      if (route is! Map<String, dynamic>) {
        throw const NaverDirectionsException(
          'Naver Directions route was not found.',
        );
      }

      final routes = route['trafast'];
      if (routes is! List || routes.isEmpty) {
        throw const NaverDirectionsException(
          'Naver Directions fast route is empty.',
        );
      }

      final firstRoute = routes.first;
      if (firstRoute is! Map<String, dynamic>) {
        throw const NaverDirectionsException(
          'Naver Directions route summary is missing.',
        );
      }

      final summary = firstRoute['summary'];
      if (summary is! Map<String, dynamic>) {
        throw const NaverDirectionsException(
          'Naver Directions summary is missing.',
        );
      }

      return NaverDirectionSummary(
        durationMilliseconds: (summary['duration'] as num?)?.toInt() ?? 0,
        distanceMeters: (summary['distance'] as num?)?.toInt() ?? 0,
      );
    } finally {
      if (ownsClient) {
        client.close();
      }
    }
  }
}

class NaverDirectionSummary {
  const NaverDirectionSummary({
    required this.durationMilliseconds,
    required this.distanceMeters,
  });

  final int durationMilliseconds;
  final int distanceMeters;

  int get durationMinutes => (durationMilliseconds / 60000).ceil();
}

class NaverDirectionCredentials {
  const NaverDirectionCredentials({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;

  bool get isReady => clientId.isNotEmpty && clientSecret.isNotEmpty;
}

class NaverDirectionsException implements Exception {
  const NaverDirectionsException(this.message);

  final String message;

  @override
  String toString() => message;
}
