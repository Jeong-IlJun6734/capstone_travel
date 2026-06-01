import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _naverClientIdAssetPath = 'server/NAVER_CLIENT_ID.txt';
const _naverClientSecretAssetPath = 'server/NAVER_CLIENT_SECRET.txt';
const _naverClientId = String.fromEnvironment('NAVER_CLIENT_ID');
const _naverClientSecret = String.fromEnvironment('NAVER_CLIENT_SECRET');

class NaverSearchCredentialsLoader {
  const NaverSearchCredentialsLoader();

  Future<NaverSearchCredentials> load() async {
    final envCredentials = NaverSearchCredentials(
      clientId: _naverClientId.trim(),
      clientSecret: _naverClientSecret.trim(),
    );
    if (envCredentials.isReady) {
      return envCredentials;
    }

    try {
      final values = await Future.wait([
        rootBundle.loadString(_naverClientIdAssetPath),
        rootBundle.loadString(_naverClientSecretAssetPath),
      ]);
      return NaverSearchCredentials(
        clientId: values[0].trim(),
        clientSecret: values[1].trim(),
      );
    } catch (_) {
      return const NaverSearchCredentials(clientId: '', clientSecret: '');
    }
  }
}

class NaverLocalSearchService {
  const NaverLocalSearchService({
    http.Client? client,
    NaverSearchCredentialsLoader credentialsLoader =
        const NaverSearchCredentialsLoader(),
  }) : _client = client,
       _credentialsLoader = credentialsLoader;

  final http.Client? _client;
  final NaverSearchCredentialsLoader _credentialsLoader;

  Future<List<NaverLocalPlace>> search({
    required String query,
    int display = 10,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }

    final credentials = await _credentialsLoader.load();
    if (!credentials.isReady) {
      throw const NaverLocalSearchException('네이버 지역 검색 API 키와 시크릿이 필요합니다.');
    }

    final uri = Uri.https('openapi.naver.com', '/v1/search/local.json', {
      'query': trimmedQuery,
      'display': display.clamp(1, 30).toString(),
      'start': '1',
      'sort': 'random',
    });

    final client = _client ?? http.Client();
    final response = await client.get(
      uri,
      headers: {
        'X-Naver-Client-Id': credentials.clientId,
        'X-Naver-Client-Secret': credentials.clientSecret,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NaverLocalSearchException(
        '네이버 지역 검색 실패: HTTP ${response.statusCode} ${utf8.decode(response.bodyBytes)}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final items = decoded['items'];
    if (items is! List) {
      return const [];
    }

    return items
        .whereType<Map<String, dynamic>>()
        .map(NaverLocalPlace.fromJson)
        .toList(growable: false);
  }
}

class NaverLocalPlace {
  const NaverLocalPlace({
    required this.title,
    required this.category,
    required this.address,
    required this.roadAddress,
    required this.link,
    required this.longitude,
    required this.latitude,
  });

  factory NaverLocalPlace.fromJson(Map<String, dynamic> json) {
    return NaverLocalPlace(
      title: _cleanText(json['title'] as String? ?? ''),
      category: _cleanText(json['category'] as String? ?? ''),
      address: _cleanText(json['address'] as String? ?? ''),
      roadAddress: _cleanText(json['roadAddress'] as String? ?? ''),
      link: json['link'] as String? ?? '',
      longitude: _coordinateFromNaver(json['mapx']),
      latitude: _coordinateFromNaver(json['mapy']),
    );
  }

  final String title;
  final String category;
  final String address;
  final String roadAddress;
  final String link;
  final double? longitude;
  final double? latitude;

  String get primaryCategory {
    final parts = category.split('>').where((part) => part.trim().isNotEmpty);
    return parts.isEmpty ? '장소' : parts.last.trim();
  }

  String get displayAddress {
    if (roadAddress.isNotEmpty) return roadAddress;
    return address;
  }

  static String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  static double? _coordinateFromNaver(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;

    final parsed = double.tryParse(text);
    if (parsed == null) return null;

    return parsed / 10000000;
  }
}

class NaverLocalSearchException implements Exception {
  const NaverLocalSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NaverSearchCredentials {
  const NaverSearchCredentials({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;

  bool get isReady => clientId.isNotEmpty && clientSecret.isNotEmpty;
}
