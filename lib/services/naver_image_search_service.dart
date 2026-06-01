import 'dart:convert';

import 'package:http/http.dart' as http;

import 'naver_local_search_service.dart';

class NaverImageSearchService {
  const NaverImageSearchService({
    http.Client? client,
    NaverSearchCredentialsLoader credentialsLoader =
        const NaverSearchCredentialsLoader(),
  }) : _client = client,
       _credentialsLoader = credentialsLoader;

  final http.Client? _client;
  final NaverSearchCredentialsLoader _credentialsLoader;

  Future<List<NaverImageResult>> search({
    required String query,
    int display = 5,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return const [];

    final credentials = await _credentialsLoader.load();
    if (!credentials.isReady) {
      throw const NaverImageSearchException('네이버 이미지 검색 API 키와 시크릿이 필요합니다.');
    }

    final uri = Uri.https('openapi.naver.com', '/v1/search/image', {
      'query': trimmedQuery,
      'display': display.clamp(1, 30).toString(),
      'start': '1',
      'sort': 'sim',
      'filter': 'medium',
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
      throw NaverImageSearchException(
        '네이버 이미지 검색 실패: HTTP ${response.statusCode} ${utf8.decode(response.bodyBytes)}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final items = decoded['items'];
    if (items is! List) return const [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(NaverImageResult.fromJson)
        .where((image) => image.thumbnail.isNotEmpty)
        .toList(growable: false);
  }
}

class NaverImageResult {
  const NaverImageResult({
    required this.title,
    required this.link,
    required this.thumbnail,
  });

  factory NaverImageResult.fromJson(Map<String, dynamic> json) {
    return NaverImageResult(
      title: _cleanText(json['title'] as String? ?? ''),
      link: json['link'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
    );
  }

  final String title;
  final String link;
  final String thumbnail;

  static String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }
}

class NaverImageSearchException implements Exception {
  const NaverImageSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}
