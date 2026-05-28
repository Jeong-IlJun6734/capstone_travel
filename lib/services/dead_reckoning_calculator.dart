import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'step_classifier_model.dart';
import 'self_supervised_step_model.dart';
import 'step_length_model.dart';

class SensorSample {
  const SensorSample({
    required this.timestamp,
    required this.accelerometer,
    required this.linearAcceleration,
    required this.gyroscope,
    required this.magnetometer,
    this.isPhoneFlat = false,
    this.geomagneticRotationAzimuth,
    this.gameRotationAzimuth,
  });

  final DateTime timestamp;
  final vm.Vector3 accelerometer;
  final vm.Vector3 linearAcceleration;
  final vm.Vector3 gyroscope;
  final vm.Vector3 magnetometer;
  final bool isPhoneFlat;
  final double? geomagneticRotationAzimuth;
  final double? gameRotationAzimuth;
}

class DeadReckoningState {
  const DeadReckoningState({
    required this.position,
    required this.headingRadians,
    required this.stepCount,
    required this.lastStepLengthMeters,
    required this.recentStepIntervals,
    required this.lastStepHeadingRadians,
    required this.thresholdCrossings,
    required this.totalDistanceMeters,
    required this.filteredAccelerationMagnitude,
    required this.activeStepThreshold,
    required this.lastStepTimestamp,
    required this.lastStepDecisionSource,
    required this.lastStepDecisionConfidence,
  });

  factory DeadReckoningState.initial() {
    return DeadReckoningState(
      position: vm.Vector2.zero(),
      headingRadians: 0,
      stepCount: 0,
      lastStepLengthMeters: 0,
      recentStepIntervals: const <double>[],
      lastStepHeadingRadians: null,
      thresholdCrossings: 0,
      totalDistanceMeters: 0,
      filteredAccelerationMagnitude: 0,
      activeStepThreshold: 0,
      lastStepTimestamp: null,
      lastStepDecisionSource: 'Learned classifier',
      lastStepDecisionConfidence: 0,
    );
  }

  final vm.Vector2 position;
  final double headingRadians;
  final int stepCount;
  final double lastStepLengthMeters;
  final List<double> recentStepIntervals;
  final double? lastStepHeadingRadians;
  final int thresholdCrossings;
  final double totalDistanceMeters;
  final double filteredAccelerationMagnitude;
  final double activeStepThreshold;
  final DateTime? lastStepTimestamp;
  final String lastStepDecisionSource;
  final double lastStepDecisionConfidence;

  DeadReckoningState copyWith({
    vm.Vector2? position,
    double? headingRadians,
    int? stepCount,
    double? lastStepLengthMeters,
    List<double>? recentStepIntervals,
    double? lastStepHeadingRadians,
    int? thresholdCrossings,
    double? totalDistanceMeters,
    double? filteredAccelerationMagnitude,
    double? activeStepThreshold,
    DateTime? lastStepTimestamp,
    String? lastStepDecisionSource,
    double? lastStepDecisionConfidence,
    bool clearLastStepTimestamp = false,
  }) {
    return DeadReckoningState(
      position: position ?? this.position,
      headingRadians: headingRadians ?? this.headingRadians,
      stepCount: stepCount ?? this.stepCount,
      lastStepLengthMeters: lastStepLengthMeters ?? this.lastStepLengthMeters,
      recentStepIntervals: recentStepIntervals ?? this.recentStepIntervals,
      lastStepHeadingRadians:
          lastStepHeadingRadians ?? this.lastStepHeadingRadians,
      thresholdCrossings: thresholdCrossings ?? this.thresholdCrossings,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      filteredAccelerationMagnitude:
          filteredAccelerationMagnitude ?? this.filteredAccelerationMagnitude,
      activeStepThreshold: activeStepThreshold ?? this.activeStepThreshold,
      lastStepTimestamp: clearLastStepTimestamp
          ? null
          : (lastStepTimestamp ?? this.lastStepTimestamp),
      lastStepDecisionSource:
          lastStepDecisionSource ?? this.lastStepDecisionSource,
      lastStepDecisionConfidence:
          lastStepDecisionConfidence ?? this.lastStepDecisionConfidence,
    );
  }
}

class DeadReckoningConfig {
  const DeadReckoningConfig({
    this.stepSensitivity = 0.38,
    this.baseStepLengthMeters = 0.917,
    this.minimumStepLengthMeters = 0.832,
    this.maximumStepLengthMeters = 0.95,
    this.minStepGap = const Duration(milliseconds: 420),
    this.headingSmoothing = 0.2,
    this.accelerationFilterAlpha = 0.84,
    this.stepBaselineAlpha = 0.96,
    this.stepRearmHysteresis = 0.35,
    this.minimumStepPeak = 0.8,
    this.maximumImuStepGyroscopeMagnitude = 3.2,
    this.maximumRapidTurnDegrees = 95,
    this.rapidTurnWindow = const Duration(milliseconds: 1200),
    this.maximumAngularVelocityDegreesPerSecond = 120,
    this.rapidTurnCooldown = const Duration(milliseconds: 650),
  });

  final double stepSensitivity;
  final double baseStepLengthMeters;
  final double minimumStepLengthMeters;
  final double maximumStepLengthMeters;
  final Duration minStepGap;
  final double headingSmoothing;
  final double accelerationFilterAlpha;
  final double stepBaselineAlpha;
  final double stepRearmHysteresis;
  final double minimumStepPeak;
  final double maximumImuStepGyroscopeMagnitude;
  final double maximumRapidTurnDegrees;
  final Duration rapidTurnWindow;
  final double maximumAngularVelocityDegreesPerSecond;
  final Duration rapidTurnCooldown;
}

class DeadReckoningCalculator {
  DeadReckoningCalculator({DeadReckoningConfig? config})
    : _config = config ?? const DeadReckoningConfig();

  final DeadReckoningConfig _config;
  StepClassifierModel? _stepClassifierModel;
  SelfSupervisedStepModel? _selfSupervisedStepModel;
  StepLengthModel? _stepLengthModel;

  double? _filteredAccelerationMagnitude;
  double? _activeStepThreshold;
  double? _dynamicAverageAccelerationMagnitude;
  double? _initialGameRotationAzimuth;
  double? _lastHeadingSampleRadians;
  DateTime? _lastHeadingSampleTimestamp;
  DateTime? _stepBlockedUntil;
  double _lastHeadingChangeDegrees = 0;
  double _lastAngularVelocityDegreesPerSecond = 0;
  String _lastStepDecisionSource = 'Learned classifier';
  double _lastStepDecisionConfidence = 0;
  final List<double> _recentUserAccelerationMagnitudes = <double>[];
  final List<double> _recentGyroscopeMagnitudes = <double>[];
  final List<double> _recentHeadingChanges = <double>[];
  static const int _featureWindowSize = 9;

  void setStepClassifierModel(StepClassifierModel? model) {
    _stepClassifierModel = model;
  }

  void setSelfSupervisedStepModel(SelfSupervisedStepModel? model) {
    _selfSupervisedStepModel = model;
  }

  void setStepLengthModel(StepLengthModel? model) {
    _stepLengthModel = model;
  }

  DeadReckoningState processSample(
    SensorSample sample,
    DeadReckoningState current,
  ) {
    final heading = _estimateHeading(sample, current);
    final nextStepState = _updateStepState(sample, current, heading);
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
        lastStepDecisionSource: nextStepState.decisionSource,
        lastStepDecisionConfidence: nextStepState.decisionConfidence,
      );
    }

    final nextStepLengthMeters = _estimateStepLengthMeters(
      sample: sample,
      current: current,
      filteredMagnitude: _filteredAccelerationMagnitude ?? 0,
      magnitude: _filteredAccelerationMagnitude ?? 0,
      heading: heading,
      activeThreshold: _activeStepThreshold ?? current.activeStepThreshold,
      gyroscopeMagnitude: sample.gyroscope.length,
    );
    final nextPosition = vm.Vector2(
      current.position.x + nextStepLengthMeters * math.cos(heading),
      current.position.y + nextStepLengthMeters * math.sin(heading),
    );
    final nextRecentStepIntervals = <double>[
      ...current.recentStepIntervals,
      if (current.lastStepTimestamp != null)
        sample.timestamp.difference(current.lastStepTimestamp!).inMilliseconds /
            1000.0,
    ];
    if (nextRecentStepIntervals.length > 5) {
      nextRecentStepIntervals.removeRange(
        0,
        nextRecentStepIntervals.length - 5,
      );
    }

    return current.copyWith(
      position: nextPosition,
      headingRadians: heading,
      stepCount: nextStepCount,
      lastStepLengthMeters: nextStepLengthMeters,
      recentStepIntervals: nextRecentStepIntervals,
      thresholdCrossings: nextStepState.thresholdCrossings,
      totalDistanceMeters: current.totalDistanceMeters + nextStepLengthMeters,
      filteredAccelerationMagnitude:
          _filteredAccelerationMagnitude ??
          current.filteredAccelerationMagnitude,
      activeStepThreshold: _activeStepThreshold ?? current.activeStepThreshold,
      lastStepHeadingRadians: heading,
      lastStepTimestamp: sample.timestamp,
      lastStepDecisionSource: nextStepState.decisionSource,
      lastStepDecisionConfidence: nextStepState.decisionConfidence,
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

  _StepState _updateStepState(
    SensorSample sample,
    DeadReckoningState current,
    double heading,
  ) {
    final rawMagnitude = sample.linearAcceleration.length;
    final gyroscopeMagnitude = sample.gyroscope.length;
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
    _activeStepThreshold = upperThreshold;
    final rapidTurnDetected = _updateRapidTurnState(
      heading: heading,
      timestamp: sample.timestamp,
    );

    final lastStepTimestamp = current.lastStepTimestamp;
    final recentTurnTooLarge =
        lastStepTimestamp != null &&
        current.lastStepHeadingRadians != null &&
        sample.timestamp.difference(lastStepTimestamp) <=
            _config.rapidTurnWindow &&
        _headingDeltaDegrees(heading, current.lastStepHeadingRadians!) >
            _config.maximumRapidTurnDegrees;
    _pushSampleHistory(sample, gyroscopeMagnitude);

    final modelAccepted = _passesLearnedStepModel(
      sample: sample,
      current: current,
      magnitude: magnitude,
      activeThreshold: upperThreshold,
      gyroscopeMagnitude: gyroscopeMagnitude,
      heading: heading,
    );

    final stepBlocked =
        _stepBlockedUntil != null &&
        !sample.timestamp.isAfter(_stepBlockedUntil!);
    final spacingSatisfied =
        lastStepTimestamp == null ||
        sample.timestamp.difference(lastStepTimestamp) >= _config.minStepGap;
    final shouldCountStep =
        modelAccepted &&
        spacingSatisfied &&
        !rapidTurnDetected &&
        !stepBlocked &&
        gyroscopeMagnitude <= _config.maximumImuStepGyroscopeMagnitude &&
        !recentTurnTooLarge;

    if (shouldCountStep) {
      _stepBlockedUntil = sample.timestamp.add(_config.minStepGap);
      return _StepState(
        stepCount: current.stepCount + 1,
        thresholdCrossings: current.thresholdCrossings + 1,
        decisionSource: _lastStepDecisionSource,
        decisionConfidence: _lastStepDecisionConfidence,
      );
    }

    return _StepState(
      stepCount: current.stepCount,
      thresholdCrossings: current.thresholdCrossings,
      decisionSource: _lastStepDecisionSource,
      decisionConfidence: _lastStepDecisionConfidence,
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

  double _headingDeltaDegrees(double a, double b) {
    final delta = (a - b).abs();
    final normalizedDelta = delta > math.pi ? (2 * math.pi) - delta : delta;
    return normalizedDelta * 180 / math.pi;
  }

  bool _updateRapidTurnState({
    required double heading,
    required DateTime timestamp,
  }) {
    final previousHeading = _lastHeadingSampleRadians;
    final previousTimestamp = _lastHeadingSampleTimestamp;
    _lastHeadingSampleRadians = heading;
    _lastHeadingSampleTimestamp = timestamp;

    if (previousHeading == null || previousTimestamp == null) {
      return false;
    }

    final dtMilliseconds = timestamp
        .difference(previousTimestamp)
        .inMilliseconds;
    if (dtMilliseconds <= 0) {
      return false;
    }

    final headingDeltaDegrees = _headingDeltaDegrees(heading, previousHeading);
    final angularVelocityDegreesPerSecond =
        headingDeltaDegrees / (dtMilliseconds / 1000.0);
    _lastHeadingChangeDegrees = headingDeltaDegrees;
    _lastAngularVelocityDegreesPerSecond = angularVelocityDegreesPerSecond;
    _pushRecentValue(_recentHeadingChanges, headingDeltaDegrees);

    if (angularVelocityDegreesPerSecond <
        _config.maximumAngularVelocityDegreesPerSecond) {
      return false;
    }

    _stepBlockedUntil = timestamp.add(_config.rapidTurnCooldown);
    return true;
  }

  bool _passesLearnedStepModel({
    required SensorSample sample,
    required DeadReckoningState current,
    required double magnitude,
    required double activeThreshold,
    required double gyroscopeMagnitude,
    required double heading,
  }) {
    final selfSupervisedModel = _selfSupervisedStepModel;
    if (selfSupervisedModel != null) {
      final features = _buildStepFeatureVector(
        sample: sample,
        current: current,
        magnitude: magnitude,
        activeThreshold: activeThreshold,
        gyroscopeMagnitude: gyroscopeMagnitude,
        heading: heading,
      );
      final probability = selfSupervisedModel.stepProbability(features);
      _lastStepDecisionSource = 'Self-supervised model';
      _lastStepDecisionConfidence = probability;
      return probability >= selfSupervisedModel.stepDecisionThreshold;
    }

    final model = _stepClassifierModel;
    if (model == null) {
      _lastStepDecisionSource = 'Model unavailable';
      _lastStepDecisionConfidence = 0;
      return false;
    }

    final features = _buildStepFeatureVector(
      sample: sample,
      current: current,
      magnitude: magnitude,
      activeThreshold: activeThreshold,
      gyroscopeMagnitude: gyroscopeMagnitude,
      heading: heading,
    );

    final baseProbability = model.predictProbability(features);
    final secondsSincePrevStep = features[14];
    final headingChangeSincePrevStep = features[15];
    final headingChangeRateSincePrevStep = features[18];
    final thresholdMarginRatio = features[6];
    final userAccelerationMagnitude = features[0];
    final filteredToUserAccelRatio = features[19];
    final accelToGyroRatio = features[20];
    final cadenceScore = _cadenceScore(
      secondsSincePrevStep: secondsSincePrevStep,
      recentStepIntervalMean: _mean(current.recentStepIntervals),
      recentStepIntervalStd: _stddev(current.recentStepIntervals),
    );
    final motionScore = _motionScore(
      magnitude: magnitude,
      activeThreshold: activeThreshold,
      thresholdMarginRatio: thresholdMarginRatio,
      userAccelerationMagnitude: userAccelerationMagnitude,
      filteredToUserAccelRatio: filteredToUserAccelRatio,
      accelToGyroRatio: accelToGyroRatio,
      gyroscopeMagnitude: gyroscopeMagnitude,
    );
    final stabilityScore = _stabilityScore(
      headingChangeSincePrevStep: headingChangeSincePrevStep,
      headingChangeRateSincePrevStep: headingChangeRateSincePrevStep,
      recentHeadingChange: _lastHeadingChangeDegrees,
      angularVelocityDegreesPerSecond: _lastAngularVelocityDegreesPerSecond,
    );

    final calibratedProbability = _clamp01(
      0.58 * baseProbability +
          0.16 * motionScore +
          0.14 * cadenceScore +
          0.12 * stabilityScore,
    );
    final dynamicThreshold = _clamp01(
      model.decisionThreshold +
          (current.recentStepIntervals.length >= 2 ? -0.02 : 0.03) +
          (stabilityScore < 0.35 ? 0.05 : 0.0),
    );

    final accepted = calibratedProbability >= dynamicThreshold;
    _lastStepDecisionSource = 'Learned classifier';
    _lastStepDecisionConfidence = calibratedProbability;
    return accepted;
  }

  double _cadenceScore({
    required double secondsSincePrevStep,
    required double recentStepIntervalMean,
    required double recentStepIntervalStd,
  }) {
    final cadenceTarget = recentStepIntervalMean > 0
        ? recentStepIntervalMean
        : 0.9;
    final cadenceSpread = math.max(0.25, recentStepIntervalStd + 0.18);
    final cadenceDelta = (secondsSincePrevStep - cadenceTarget).abs();
    final normalizedCadence =
        1.0 - _normalizedProgress(cadenceDelta, 0.0, cadenceSpread * 2.2);
    return _clamp01(0.2 + 0.8 * normalizedCadence);
  }

  double _motionScore({
    required double magnitude,
    required double activeThreshold,
    required double thresholdMarginRatio,
    required double userAccelerationMagnitude,
    required double filteredToUserAccelRatio,
    required double accelToGyroRatio,
    required double gyroscopeMagnitude,
  }) {
    final thresholdScore = _normalizedProgress(thresholdMarginRatio, -0.1, 0.7);
    final filteredScore = _normalizedProgress(
      filteredToUserAccelRatio,
      0.75,
      1.65,
    );
    final accelScore = _normalizedProgress(userAccelerationMagnitude, 1.0, 4.8);
    final gyroPenalty = 1.0 - _normalizedProgress(gyroscopeMagnitude, 0.0, 2.2);
    final accelGyroBalance = _normalizedProgress(accelToGyroRatio, 1.1, 9.0);
    final absoluteMotionScore = _normalizedProgress(
      magnitude,
      activeThreshold - 0.15,
      activeThreshold + 0.85,
    );

    return _clamp01(
      0.30 * thresholdScore +
          0.20 * filteredScore +
          0.18 * accelScore +
          0.16 * accelGyroBalance +
          0.10 * absoluteMotionScore +
          0.06 * gyroPenalty,
    );
  }

  double _stabilityScore({
    required double headingChangeSincePrevStep,
    required double headingChangeRateSincePrevStep,
    required double recentHeadingChange,
    required double angularVelocityDegreesPerSecond,
  }) {
    final headingScore =
        1.0 - _normalizedProgress(headingChangeSincePrevStep.abs(), 0.0, 55.0);
    final rateScore =
        1.0 -
        _normalizedProgress(headingChangeRateSincePrevStep.abs(), 0.0, 45.0);
    final recentScore =
        1.0 - _normalizedProgress(recentHeadingChange, 0.0, 40.0);
    final angularScore =
        1.0 -
        _normalizedProgress(angularVelocityDegreesPerSecond.abs(), 0.0, 70.0);
    return _clamp01(
      0.34 * headingScore +
          0.26 * rateScore +
          0.20 * recentScore +
          0.20 * angularScore,
    );
  }

  void _pushSampleHistory(SensorSample sample, double gyroscopeMagnitude) {
    _pushRecentValue(
      _recentUserAccelerationMagnitudes,
      sample.linearAcceleration.length,
    );
    _pushRecentValue(_recentGyroscopeMagnitudes, gyroscopeMagnitude);
  }

  void _pushRecentValue(List<double> values, double value) {
    values.add(value);
    if (values.length > _featureWindowSize) {
      values.removeAt(0);
    }
  }

  double _mean(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    return values.reduce((double a, double b) => a + b) / values.length;
  }

  double _maxValue(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    return values.reduce(math.max);
  }

  double _stddev(List<double> values) {
    if (values.length < 2) {
      return 0;
    }
    final average = _mean(values);
    final variance =
        values
            .map((double value) => math.pow(value - average, 2).toDouble())
            .reduce((double a, double b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }

  double _tiltGyroscopeMagnitude(vm.Vector3 gyroscope) {
    return math.sqrt(gyroscope.x * gyroscope.x + gyroscope.y * gyroscope.y);
  }

  double _estimateStepLengthMeters({
    required SensorSample sample,
    required DeadReckoningState current,
    required double magnitude,
    required double filteredMagnitude,
    required double heading,
    required double activeThreshold,
    required double gyroscopeMagnitude,
  }) {
    final features = _buildStepFeatureVector(
      sample: sample,
      current: current,
      magnitude: magnitude,
      activeThreshold: activeThreshold,
      gyroscopeMagnitude: gyroscopeMagnitude,
      heading: heading,
    );

    final selfSupervisedModel = _selfSupervisedStepModel;
    if (selfSupervisedModel != null) {
      return selfSupervisedModel.predictStepLengthMeters(features);
    }

    final model = _stepLengthModel;
    if (model != null) {
      return model.predictMeters(features);
    }

    const baselineIntervalSeconds = 1.1;
    const fastStepIntervalSeconds = 0.55;
    const slowStepIntervalSeconds = 1.7;
    const baselineMotionMagnitude = 2.85;
    const baselineFilteredMagnitude = 2.05;

    final latestIntervalSeconds = current.lastStepTimestamp == null
        ? baselineIntervalSeconds
        : math.max(
            0.35,
            sample.timestamp
                    .difference(current.lastStepTimestamp!)
                    .inMilliseconds /
                1000.0,
          );
    final cadenceProgress = _normalizedProgress(
      baselineIntervalSeconds - latestIntervalSeconds,
      baselineIntervalSeconds - slowStepIntervalSeconds,
      baselineIntervalSeconds - fastStepIntervalSeconds,
    );

    final motionMagnitude = sample.linearAcceleration.length;
    final motionProgress = _normalizedProgress(motionMagnitude, 1.3, 4.6);
    final filteredProgress = _normalizedProgress(filteredMagnitude, 1.3, 3.6);
    final headingStabilityProgress =
        1.0 -
        _normalizedProgress(
          current.lastStepHeadingRadians == null
              ? 0.0
              : _headingDeltaDegrees(heading, current.lastStepHeadingRadians!),
          0,
          45,
        );

    final blendedProgress =
        0.4 * cadenceProgress +
        0.3 * motionProgress +
        0.2 * filteredProgress +
        0.1 * headingStabilityProgress;

    final centeredBlend = (blendedProgress * 2.0) - 1.0;
    final cadenceAdjustment =
        (baselineIntervalSeconds - latestIntervalSeconds) * 0.07;
    final motionAdjustment =
        ((motionMagnitude - baselineMotionMagnitude) /
            baselineMotionMagnitude) *
        0.055;
    final filteredAdjustment =
        ((filteredMagnitude - baselineFilteredMagnitude) /
            baselineFilteredMagnitude) *
        0.03;

    final estimatedStepLength =
        _config.baseStepLengthMeters +
        centeredBlend * 0.03 +
        cadenceAdjustment +
        motionAdjustment +
        filteredAdjustment;
    return estimatedStepLength.clamp(
      _config.minimumStepLengthMeters,
      _config.maximumStepLengthMeters,
    );
  }

  List<double> _buildStepFeatureVector({
    required SensorSample sample,
    required DeadReckoningState current,
    required double magnitude,
    required double activeThreshold,
    required double gyroscopeMagnitude,
    required double heading,
  }) {
    final userAccelerationMagnitude = sample.linearAcceleration.length;
    final thresholdMargin = magnitude - activeThreshold;
    final thresholdMarginRatio =
        thresholdMargin / math.max(activeThreshold, 1e-3);
    final secondsSincePrevStep = current.lastStepTimestamp == null
        ? 0.0
        : sample.timestamp
                  .difference(current.lastStepTimestamp!)
                  .inMilliseconds /
              1000.0;
    final headingChangeSincePrevStep = current.lastStepHeadingRadians == null
        ? 0.0
        : _headingDeltaDegrees(heading, current.lastStepHeadingRadians!);
    final headingChangeRateSincePrevStep = secondsSincePrevStep <= 1e-6
        ? 0.0
        : headingChangeSincePrevStep / secondsSincePrevStep;
    final accelToGyroRatio =
        userAccelerationMagnitude / math.max(gyroscopeMagnitude, 0.05);
    final filteredToUserAccelRatio =
        magnitude / math.max(userAccelerationMagnitude, 0.05);

    return <double>[
      userAccelerationMagnitude,
      gyroscopeMagnitude,
      _tiltGyroscopeMagnitude(sample.gyroscope),
      magnitude,
      activeThreshold,
      thresholdMargin,
      thresholdMarginRatio,
      _lastHeadingChangeDegrees,
      _lastAngularVelocityDegreesPerSecond,
      _mean(_recentUserAccelerationMagnitudes),
      _stddev(_recentUserAccelerationMagnitudes),
      _mean(_recentGyroscopeMagnitudes),
      _stddev(_recentGyroscopeMagnitudes),
      _maxValue(_recentHeadingChanges),
      secondsSincePrevStep,
      headingChangeSincePrevStep,
      _mean(current.recentStepIntervals),
      _stddev(current.recentStepIntervals),
      headingChangeRateSincePrevStep,
      filteredToUserAccelRatio,
      accelToGyroRatio,
    ];
  }

  double _normalizedProgress(double value, double minValue, double maxValue) {
    if (maxValue <= minValue) {
      return 0.5;
    }
    return ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
  }

  double _clamp01(double value) {
    return value.clamp(0.0, 1.0);
  }
}

class _StepState {
  const _StepState({
    required this.stepCount,
    required this.thresholdCrossings,
    required this.decisionSource,
    required this.decisionConfidence,
  });

  final int stepCount;
  final int thresholdCrossings;
  final String decisionSource;
  final double decisionConfidence;
}
