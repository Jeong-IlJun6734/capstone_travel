import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:route_in/models/tmap_route.dart';
import 'package:route_in/services/tmap_route_service.dart';

void main() {
  test('parses transit route legs', () async {
    final service = TmapRouteService(
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://apis.openapi.sk.com/transit/routes',
        );
        expect(request.method, 'POST');

        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'metaData': {
                'plan': {
                  'itineraries': [
                    {
                      'totalTime': 1260,
                      'totalDistance': 5200,
                      'transferCount': 1,
                      'legs': [
                        {
                          'mode': 'WALK',
                          'steps': [
                            {'linestring': '126.9768,37.5723 126.9770,37.5720'},
                          ],
                        },
                        {
                          'mode': 'BUS',
                          'route': '7016',
                          'passShape': {
                            'linestring': '126.9770,37.5720 126.9783,37.5666',
                          },
                        },
                      ],
                    },
                  ],
                },
              },
            }),
          ),
          200,
        );
      }),
    );

    final route = await service.fetchRoute(
      mode: TmapRouteMode.transit,
      startLatitude: 37.5723,
      startLongitude: 126.9768,
      endLatitude: 37.5666,
      endLongitude: 126.9783,
      destinationName: 'Destination 1',
    );

    expect(route.mode, TmapRouteMode.transit);
    expect(route.segments, hasLength(2));
    expect(route.segments.first.mode, TmapRouteSegmentMode.walk);
    expect(route.segments.last.mode, TmapRouteSegmentMode.transit);
    expect(route.totalTimeSeconds, 1260);
    expect(route.totalDistanceMeters, 5200);
    expect(route.transferCount, 1);
  });

  test('parses car GeoJSON line segments', () async {
    final service = TmapRouteService(
      client: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [126.9768, 37.5723],
                  },
                  'properties': {'totalTime': 360, 'totalDistance': 1900},
                },
                {
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      [126.9768, 37.5723],
                      [126.9783, 37.5666],
                    ],
                  },
                  'properties': {'name': 'Main road'},
                },
              ],
            }),
          ),
          200,
        );
      }),
    );

    final route = await service.fetchRoute(
      mode: TmapRouteMode.car,
      startLatitude: 37.5723,
      startLongitude: 126.9768,
      endLatitude: 37.5666,
      endLongitude: 126.9783,
      destinationName: 'Destination 1',
    );

    expect(route.segments, hasLength(1));
    expect(route.segments.single.mode, TmapRouteSegmentMode.car);
    expect(route.totalTimeSeconds, 360);
    expect(route.totalDistanceMeters, 1900);
  });
}
