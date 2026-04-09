import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

class SensorSample {
  const SensorSample({
    required this.timestamp,
    required this.accelerometer,
    required this.linearAcceleration,
    required this.gyroscope,
    required this.magnetometer,
    this.hardwareStepDetected = false,
    this.preferHardwareStepDetector = false,
    this.geomagneticRotationAzimuth,
    this.gameRotationAzimuth,
  });

  final DateTime timestamp;
  final vm.Vector3 accelerometer;
  final vm.Vector3 linearAcceleration;
  final vm.Vector3 gyroscope;
  final vm.Vector3 magnetometer;
  final bool hardwareStepDetected;
  final bool preferHardwareStepDetector;
  final double? geomagneticRotationAzimuth;
  final double? gameRotationAzimuth;
}

class DeadReckoningState {
  const DeadReckoningState({
    required this.position,
    required this.headingRadians,
    required this.stepCount,
    required this.thresholdCrossings,
    required this.totalDistanceMeters,
    required this.filteredAccelerationMagnitude,
    required this.activeStepThreshold,
    required this.lastStepTimestamp,
  });

  factory DeadReckoningState.initial() {
    return DeadReckoningState(
      position: vm.Vector2.zero(),
      headingRadians: 0,
      stepCount: 0,
      thresholdCrossings: 0,
      totalDistanceMeters: 0,
      filteredAccelerationMagnitude: 0,
      activeStepThreshold: 0,
      lastStepTimestamp: null,
    );
  }

  final vm.Vector2 position;
  final double headingRadians;
  final int stepCount;
  final int thresholdCrossings;
  final double totalDistanceMeters;
  final double filteredAccelerationMagnitude;
  final double activeStepThreshold;
  final DateTime? lastStepTimestamp;

  DeadReckoningState copyWith({
    vm.Vector2? position,
    double? headingRadians,
    int? stepCount,
    int? thresholdCrossings,
    double? totalDistanceMeters,
    double? filteredAccelerationMagnitude,
    double? activeStepThreshold,
    DateTime? lastStepTimestamp,
    bool clearLastStepTimestamp = false,
  }) {
    return DeadReckoningState(
      position: position ?? this.position,
      headingRadians: headingRadians ?? this.headingRadians,
      stepCount: stepCount ?? this.stepCount,
      thresholdCrossings: thresholdCrossings ?? this.thresholdCrossings,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      filteredAccelerationMagnitude:
          filteredAccelerationMagnitude ?? this.filteredAccelerationMagnitude,
      activeStepThreshold: activeStepThreshold ?? this.activeStepThreshold,
      lastStepTimestamp: clearLastStepTimestamp
          ? null
          : (lastStepTimestamp ?? this.lastStepTimestamp),
    );
  }
}

class DeadReckoningConfig {
  const DeadReckoningConfig({
    this.stepSensitivity = 0.55,
    this.stepLengthMeters = 0.72,
    this.minStepGap = const Duration(milliseconds: 330),
    this.headingSmoothing = 0.2,
    this.accelerationFilterAlpha = 0.84,
    this.stepBaselineAlpha = 0.96,
    this.stepRearmHysteresis = 0.35,
    this.minimumStepPeak = 1.1,
  });

  final double stepSensitivity;
  final double stepLengthMeters;
  final Duration minStepGap;
  final double headingSmoothing;
  final double accelerationFilterAlpha;
  final double stepBaselineAlpha;
  final double stepRearmHysteresis;
  final double minimumStepPeak;
}

class DeadReckoningCalculator {
  DeadReckoningCalculator({DeadReckoningConfig? config})
    : _config = config ?? const DeadReckoningConfig();

  final DeadReckoningConfig _config;

  double? _filteredAccelerationMagnitude;
  double? _activeStepThreshold;
  double? _dynamicAverageAccelerationMagnitude;
  bool _peakFound = false;
  double? _initialGameRotationAzimuth;

  DeadReckoningState processSample(
    SensorSample sample,
    DeadReckoningState current,
  ) {
    final heading = _estimateHeading(sample, current);
    final nextStepState = _updateStepState(sample, current);
    final nextStepCount = nextStepState.stepCount;

    if (nextStepCount <= current.stepCount) {
      return current.copyWith(
        headingRadians: heading,
        thresholdCrossings: nextStepState.thresholdCrossings,
        filteredAccelerationMagnitude:
            _filteredAccelerationMagnitude ??
            current.filteredAccelerationMagnitude,
        activeStepThreshold:
            _activeStepThreshold ?? current.activeStepThreshold,
      );
    }

    final nextPosition = vm.Vector2(
      current.position.x + _config.stepLengthMeters * math.cos(heading),
      current.position.y + _config.stepLengthMeters * math.sin(heading),
    );

    return current.copyWith(
      position: nextPosition,
      headingRadians: heading,
      stepCount: nextStepCount,
      thresholdCrossings: nextStepState.thresholdCrossings,
      totalDistanceMeters: nextStepCount * _config.stepLengthMeters,
      filteredAccelerationMagnitude:
          _filteredAccelerationMagnitude ??
          current.filteredAccelerationMagnitude,
      activeStepThreshold: _activeStepThreshold ?? current.activeStepThreshold,
      lastStepTimestamp: sample.timestamp,
    );
  }

  DeadReckoningState processSamples(Iterable<SensorSample> samples) {
    var state = DeadReckoningState.initial();

    for (final sample in samples) {
      state = processSample(sample, state);
    }

    return state;
  }

  double _estimateHeading(SensorSample sample, DeadReckoningState current) {
    final geomagneticAzimuth = sample.geomagneticRotationAzimuth;
    if (geomagneticAzimuth != null) {
      return _lerpAngle(
        current.headingRadians,
        _normalizeAngle(geomagneticAzimuth),
        _config.headingSmoothing,
      );
    }

    final gameAzimuth = sample.gameRotationAzimuth;
    if (gameAzimuth == null) {
      return current.headingRadians;
    }

    final initialGameRotationAzimuth =
        _initialGameRotationAzimuth ?? gameAzimuth;
    _initialGameRotationAzimuth ??= gameAzimuth;
    final normalizedGameAzimuth = _normalizeAngle(
      gameAzimuth - initialGameRotationAzimuth,
    );

    return _lerpAngle(
      current.headingRadians,
      normalizedGameAzimuth,
      _config.headingSmoothing,
    );
  }

  _StepState _updateStepState(SensorSample sample, DeadReckoningState current) {
    final rawMagnitude = sample.linearAcceleration.length;
    _filteredAccelerationMagnitude = _lowPassScalar(
      input: rawMagnitude,
      previous: _filteredAccelerationMagnitude,
      alpha: _config.accelerationFilterAlpha,
    );

    final magnitude = _filteredAccelerationMagnitude ?? rawMagnitude;
    _dynamicAverageAccelerationMagnitude = _lowPassScalar(
      input: magnitude,
      previous: _dynamicAverageAccelerationMagnitude,
      alpha: _config.stepBaselineAlpha,
    );

    final averageMagnitude = _dynamicAverageAccelerationMagnitude ?? magnitude;
    final upperThreshold = math.max(
      _config.minimumStepPeak,
      averageMagnitude + _config.stepSensitivity,
    );
    final lowerThreshold = math.max(
      0,
      upperThreshold - _config.stepRearmHysteresis,
    );
    _activeStepThreshold = upperThreshold;

    if (sample.preferHardwareStepDetector) {
      if (!sample.hardwareStepDetected) {
        return _StepState(
          stepCount: current.stepCount,
          thresholdCrossings: current.thresholdCrossings,
        );
      }

      final lastStepTimestamp = current.lastStepTimestamp;
      if (lastStepTimestamp != null &&
          sample.timestamp.difference(lastStepTimestamp) < _config.minStepGap) {
        return _StepState(
          stepCount: current.stepCount,
          thresholdCrossings: current.thresholdCrossings,
        );
      }

      return _StepState(
        stepCount: current.stepCount + 1,
        thresholdCrossings: current.thresholdCrossings + 1,
      );
    }

    final lastStepTimestamp = current.lastStepTimestamp;
    if (magnitude > upperThreshold) {
      if (!_peakFound &&
          (lastStepTimestamp == null ||
              sample.timestamp.difference(lastStepTimestamp) >=
                  _config.minStepGap)) {
        _peakFound = true;
        return _StepState(
          stepCount: current.stepCount + 1,
          thresholdCrossings: current.thresholdCrossings + 1,
        );
      }

      return _StepState(
        stepCount: current.stepCount,
        thresholdCrossings: current.thresholdCrossings,
      );
    }

    if (magnitude < lowerThreshold && _peakFound) {
      _peakFound = false;
    }

    return _StepState(
      stepCount: current.stepCount,
      thresholdCrossings: current.thresholdCrossings,
    );
  }

  double _lowPassScalar({
    required double input,
    required double? previous,
    required double alpha,
  }) {
    if (previous == null) {
      return input;
    }

    return previous * alpha + input * (1 - alpha);
  }

  double _lerpAngle(double start, double end, double t) {
    final delta = ((end - start + math.pi) % (2 * math.pi)) - math.pi;
    return start + delta * t;
  }

  double _normalizeAngle(double angle) {
    return ((angle + math.pi) % (2 * math.pi)) - math.pi;
  }
}

class _StepState {
  const _StepState({required this.stepCount, required this.thresholdCrossings});

  final int stepCount;
  final int thresholdCrossings;
}
