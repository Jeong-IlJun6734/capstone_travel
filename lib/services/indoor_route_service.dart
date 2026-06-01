import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math.dart' as vm;

class IndoorRoute {
  const IndoorRoute({
    required this.stationName,
    required this.lineNo,
    required this.startNodeId,
    required this.endNodeId,
    required this.pathNodeIds,
    required this.nodes,
    required this.segments,
    required this.elevator,
    required this.totalDistance,
  });

  final String stationName;
  final String lineNo;
  final String startNodeId;
  final String endNodeId;
  final List<String> pathNodeIds;
  final List<IndoorRouteNode> nodes;
  final List<IndoorRouteSegment> segments;
  final IndoorRouteElevator elevator;
  final double totalDistance;

  IndoorRouteNode? nextNodeFrom(vm.Vector2 position) {
    if (nodes.isEmpty) {
      return null;
    }

    const arrivalRadius = 36.0;
    for (final node in nodes) {
      if ((node.position - position).length > arrivalRadius) {
        return node;
      }
    }
    return nodes.last;
  }

  IndoorRouteSegment? segmentToNode(String nodeId) {
    for (final segment in segments) {
      if (segment.toNodeId == nodeId) {
        return segment;
      }
    }
    return null;
  }
}

class IndoorRouteNode {
  const IndoorRouteNode({
    required this.id,
    required this.kind,
    required this.floor,
    required this.position,
    required this.isElevatorNode,
    required this.isElevatorBoardingNode,
    required this.isElevatorPassingNode,
    this.label,
    this.entranceNo,
  });

  final String id;
  final String kind;
  final String floor;
  final vm.Vector2 position;
  final bool isElevatorNode;
  final bool isElevatorBoardingNode;
  final bool isElevatorPassingNode;
  final String? label;
  final String? entranceNo;
}

class IndoorRouteSegment {
  const IndoorRouteSegment({
    required this.fromNodeId,
    required this.toNodeId,
    required this.kind,
    required this.usesElevator,
    required this.fromFloor,
    required this.toFloor,
    required this.distance,
  });

  final String fromNodeId;
  final String toNodeId;
  final String kind;
  final bool usesElevator;
  final String fromFloor;
  final String toFloor;
  final double distance;
}

class IndoorRouteElevator {
  const IndoorRouteElevator({
    required this.used,
    required this.boardingNodeIds,
    required this.passingNodeIds,
  });

  final bool used;
  final List<String> boardingNodeIds;
  final List<String> passingNodeIds;
}

class IndoorRouteService {
  IndoorRouteService({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _baseUri = Uri.parse(
    'https://stood-journalist-answers-procedures.trycloudflare.com',
  );

  final http.Client _client;

  Future<IndoorRoute> fetchRoute({
    required String line,
    required String station,
    required String startNodeId,
    required String endNodeId,
  }) async {
    final response = await _client.get(
      _baseUri.replace(
        pathSegments: ['api', 'route'],
        queryParameters: {'start': startNodeId, 'end': endNodeId},
      ),
      headers: const {'accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IndoorRouteException(
        'Indoor route request failed (${response.statusCode})',
      );
    }

    return _routeFromPayload(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  IndoorRoute _routeFromPayload(dynamic payload) {
    final map = _asMap(payload);
    final pathNodes = _asList(map['path_nodes'] ?? map['pathNodes']);
    final nodes = pathNodes.map(_nodeFromPayload).toList(growable: false);
    final path = _asList(map['path']).map((value) => '$value').toList();
    final segments = _asList(
      map['path_segments'] ?? map['pathSegments'],
    ).map(_segmentFromPayload).toList(growable: false);
    final elevator = _elevatorFromPayload(map['elevator']);

    if (nodes.isEmpty) {
      throw const IndoorRouteException('Indoor route response has no nodes.');
    }

    return IndoorRoute(
      stationName: '${map['station_name'] ?? map['stationName'] ?? ''}',
      lineNo: '${map['line_no'] ?? map['lineNo'] ?? ''}',
      startNodeId: '${map['start'] ?? ''}',
      endNodeId: '${map['end'] ?? ''}',
      pathNodeIds: path,
      nodes: nodes,
      segments: segments,
      elevator: elevator,
      totalDistance: _readDouble(map['total_distance']) ?? 0,
    );
  }

  IndoorRouteNode _nodeFromPayload(dynamic payload) {
    final map = _asMap(payload);
    final imageXy = _asList(map['image_xy'] ?? map['imageXy']);
    if (imageXy.length < 2) {
      throw const IndoorRouteException('Indoor route node has no image_xy.');
    }

    final x = _readDouble(imageXy[0]);
    final y = _readDouble(imageXy[1]);
    if (x == null || y == null) {
      throw const IndoorRouteException(
        'Indoor route node has invalid image_xy.',
      );
    }

    return IndoorRouteNode(
      id: '${map['id'] ?? ''}',
      kind: '${map['kind'] ?? ''}',
      floor: '${map['floor'] ?? ''}',
      position: vm.Vector2(x, y),
      isElevatorNode: _readBool(map['is_elevator_node']),
      isElevatorBoardingNode: _readBool(map['is_elevator_boarding_node']),
      isElevatorPassingNode: _readBool(map['is_elevator_passing_node']),
      label: _nullableString(map['label']),
      entranceNo: _nullableString(map['entrance_no'] ?? map['entranceNo']),
    );
  }

  IndoorRouteSegment _segmentFromPayload(dynamic payload) {
    final map = _asMap(payload);
    return IndoorRouteSegment(
      fromNodeId: '${map['from'] ?? ''}',
      toNodeId: '${map['to'] ?? ''}',
      kind: '${map['kind'] ?? ''}',
      usesElevator: _readBool(map['uses_elevator'] ?? map['usesElevator']),
      fromFloor: '${map['from_floor'] ?? map['fromFloor'] ?? ''}',
      toFloor: '${map['to_floor'] ?? map['toFloor'] ?? ''}',
      distance: _readDouble(map['distance']) ?? 0,
    );
  }

  IndoorRouteElevator _elevatorFromPayload(dynamic payload) {
    final map = _asMap(payload);
    return IndoorRouteElevator(
      used: _readBool(map['used']),
      boardingNodeIds: _asList(
        map['boarding_nodes'] ?? map['boardingNodes'],
      ).map((value) => '$value').toList(growable: false),
      passingNodeIds: _asList(
        map['passing_nodes'] ?? map['passingNodes'],
      ).map((value) => '$value').toList(growable: false),
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

  bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return false;
  }

  String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }
    final text = '$value';
    return text.isEmpty || text == 'null' ? null : text;
  }
}

class IndoorRouteException implements Exception {
  const IndoorRouteException(this.message);

  final String message;

  @override
  String toString() => message;
}
