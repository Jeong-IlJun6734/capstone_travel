enum TmapRouteMode {
  transit('대중교통 경로'),
  car('자동차 경로');

  const TmapRouteMode(this.label);

  final String label;
}

enum TmapRouteSegmentMode { walk, transit, car }

class TmapCoordinate {
  const TmapCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class TmapRouteSegment {
  const TmapRouteSegment({
    required this.id,
    required this.mode,
    required this.coordinates,
    required this.label,
  });

  final String id;
  final TmapRouteSegmentMode mode;
  final List<TmapCoordinate> coordinates;
  final String label;
}

class TmapRoute {
  const TmapRoute({
    required this.mode,
    required this.segments,
    required this.totalTimeSeconds,
    required this.totalDistanceMeters,
    this.transferCount,
  });

  final TmapRouteMode mode;
  final List<TmapRouteSegment> segments;
  final int totalTimeSeconds;
  final int totalDistanceMeters;
  final int? transferCount;

  List<TmapCoordinate> get allCoordinates {
    return segments
        .expand((segment) => segment.coordinates)
        .toList(growable: false);
  }
}
