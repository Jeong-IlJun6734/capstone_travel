import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../services/dead_reckoning_calculator.dart';
import '../services/self_supervised_step_model.dart';
import '../theme/route_in_palette.dart';

class IndoorNavigationPage extends StatefulWidget {
  const IndoorNavigationPage({super.key});

  @override
  State<IndoorNavigationPage> createState() => _IndoorNavigationPageState();
}

class _IndoorNavigationPageState extends State<IndoorNavigationPage> {
  static const EventChannel _rotationVectorChannel = EventChannel(
    'route_in/rotation_vectors',
  );
  static const double _flatPhoneEnterGravityRatioThreshold = 0.76;
  static const double _flatPhoneExitGravityRatioThreshold = 0.6;
  static const double _flatPhoneEnterHorizontalGravityThreshold = 6.2;
  static const double _flatPhoneExitHorizontalGravityThreshold = 8.4;
  static const int _flatPhoneEnterSampleCount = 4;
  static const int _flatPhoneExitSampleCount = 6;

  final DeadReckoningCalculator _deadReckoningCalculator =
      DeadReckoningCalculator();
  final List<String> _pendingLogLines = <String>[];

  CameraController? _cameraController;
  Future<void>? _cameraReady;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<UserAccelerometerEvent>? _userAccelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<dynamic>? _rotationVectorSubscription;

  AccelerometerEvent? _accelerometerEvent;
  UserAccelerometerEvent? _userAccelerometerEvent;
  GyroscopeEvent? _gyroscopeEvent;
  MagnetometerEvent? _magnetometerEvent;
  double? _geomagneticRotationAzimuth;
  double? _gameRotationAzimuth;
  bool? _cameraPermissionGranted;
  bool? _activityRecognitionGranted;
  DeadReckoningState _deadReckoningState = DeadReckoningState.initial();
  Timer? _logFlushTimer;
  File? _logFile;
  String? _cameraError;
  bool _hasShownCameraErrorDialog = false;
  bool _hasShownFlatPhoneDialog = false;
  bool _isFlatPhoneDialogVisible = false;
  bool _isFlushingLog = false;
  bool _isPhoneFlat = false;
  int _flatPhoneEnterStreak = 0;
  int _flatPhoneExitStreak = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initializePage());
  }

  Future<void> _initializePage() async {
    await _loadSelfSupervisedStepModel();
    await _requestPermissions();
    _cameraReady = _initializeCamera();
    _startSensorStreams();
    _startRotationVectorStream();
    await _initializeLogging();
  }

  Future<void> _loadSelfSupervisedStepModel() async {
    try {
      final model = await SelfSupervisedStepModel.loadAsset(
        'models/self_supervised_step_model.json',
      );
      _deadReckoningCalculator.setSelfSupervisedStepModel(model);
    } catch (_) {
      _deadReckoningCalculator.setSelfSupervisedStepModel(null);
    }
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final activityRecognitionStatus = await Permission.activityRecognition
        .request();

    if (!mounted) {
      return;
    }

    setState(() {
      _cameraPermissionGranted = cameraStatus.isGranted;
      _activityRecognitionGranted = activityRecognitionStatus.isGranted;
    });
  }

  Future<void> _initializeCamera() async {
    if (_cameraPermissionGranted == false) {
      _setCameraError('Camera permission denied.');
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setCameraError('No camera available on this device.');
        return;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraError = null;
        _hasShownCameraErrorDialog = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      _setCameraError('Camera initialization failed: $error');
    }
  }

  void _setCameraError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _cameraError = message;
    });
    _showCameraUnavailableDialog();
  }

  void _showCameraUnavailableDialog() {
    if (!mounted || _hasShownCameraErrorDialog) {
      return;
    }

    _hasShownCameraErrorDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('알림'),
            content: const Text('카메라를 사용할 수 없습니다!'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  if (mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('확인'),
              ),
            ],
          );
        },
      );
    });
  }

  void _handlePhoneFlatStateChanged(AccelerometerEvent event) {
    final nextState = _nextPhoneFlatState(event);
    if (nextState == null || _isPhoneFlat == nextState) {
      return;
    }

    _isPhoneFlat = nextState;

    if (nextState) {
      _showFlatPhoneDialog();
    } else {
      _dismissFlatPhoneDialog();
    }
  }

  bool? _nextPhoneFlatState(AccelerometerEvent event) {
    final isFlatCandidate = _matchesFlatEnterThreshold(event);
    final isUprightCandidate = _matchesFlatExitThreshold(event);

    if (!_isPhoneFlat) {
      if (isFlatCandidate) {
        _flatPhoneEnterStreak += 1;
      } else {
        _flatPhoneEnterStreak = 0;
      }
      _flatPhoneExitStreak = 0;
      if (_flatPhoneEnterStreak >= _flatPhoneEnterSampleCount) {
        _flatPhoneEnterStreak = 0;
        return true;
      }
      return null;
    }

    if (isUprightCandidate) {
      _flatPhoneExitStreak += 1;
    } else {
      _flatPhoneExitStreak = 0;
    }
    _flatPhoneEnterStreak = 0;
    if (_flatPhoneExitStreak >= _flatPhoneExitSampleCount) {
      _flatPhoneExitStreak = 0;
      return false;
    }
    return null;
  }

  bool _matchesFlatEnterThreshold(AccelerometerEvent event) {
    const gravity = 9.81;
    final zRatio = event.z.abs() / gravity;
    final horizontalGravity = math.sqrt(event.x * event.x + event.y * event.y);
    return zRatio >= _flatPhoneEnterGravityRatioThreshold &&
        horizontalGravity <= _flatPhoneEnterHorizontalGravityThreshold;
  }

  bool _matchesFlatExitThreshold(AccelerometerEvent event) {
    const gravity = 9.81;
    final zRatio = event.z.abs() / gravity;
    final horizontalGravity = math.sqrt(event.x * event.x + event.y * event.y);
    return zRatio <= _flatPhoneExitGravityRatioThreshold ||
        horizontalGravity >= _flatPhoneExitHorizontalGravityThreshold;
  }

  void _showFlatPhoneDialog() {
    if (!mounted || _hasShownFlatPhoneDialog) {
      return;
    }

    _hasShownFlatPhoneDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isPhoneFlat) {
        _hasShownFlatPhoneDialog = false;
        return;
      }

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return const AlertDialog(
            title: Text('주의'),
            content: Text('스마트폰을 세워주세요'),
          );
        },
      ).then((_) {
        _hasShownFlatPhoneDialog = false;
        _isFlatPhoneDialogVisible = false;
      });
      _isFlatPhoneDialogVisible = true;
    });
  }

  void _dismissFlatPhoneDialog() {
    if (!mounted || !_isFlatPhoneDialogVisible) {
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  void _startSensorStreams() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _accelerometerEvent = event;
        _handlePhoneFlatStateChanged(event);
      });
    });

    _userAccelerometerSubscription = userAccelerometerEventStream().listen((
      event,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _userAccelerometerEvent = event;
        _updateDeadReckoning();
      });
    });

    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _gyroscopeEvent = event;
      });
    });

    _magnetometerSubscription = magnetometerEventStream().listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _magnetometerEvent = event;
      });
    });
  }

  void _startRotationVectorStream() {
    _rotationVectorSubscription = _rotationVectorChannel
        .receiveBroadcastStream()
        .listen((dynamic event) {
          if (!mounted || event is! Map<Object?, Object?>) {
            return;
          }

          final geomagneticAzimuth = (event['geomagneticAzimuth'] as num?)
              ?.toDouble();
          final gameAzimuth = (event['gameAzimuth'] as num?)?.toDouble();

          setState(() {
            _geomagneticRotationAzimuth = geomagneticAzimuth;
            _gameRotationAzimuth = gameAzimuth;
          });
        });
  }

  void _updateDeadReckoning() {
    final accelerometer = _accelerometerEvent;
    final linearAcceleration = _userAccelerometerEvent;
    final gyroscope = _gyroscopeEvent;
    final magnetometer = _magnetometerEvent;

    if (accelerometer == null ||
        linearAcceleration == null ||
        gyroscope == null ||
        magnetometer == null) {
      return;
    }
    final timestamp = DateTime.now();

    final sample = SensorSample(
      timestamp: timestamp,
      accelerometer: vm.Vector3(
        accelerometer.x,
        accelerometer.y,
        accelerometer.z,
      ),
      linearAcceleration: vm.Vector3(
        linearAcceleration.x,
        linearAcceleration.y,
        linearAcceleration.z,
      ),
      gyroscope: vm.Vector3(gyroscope.x, gyroscope.y, gyroscope.z),
      magnetometer: vm.Vector3(magnetometer.x, magnetometer.y, magnetometer.z),
      isPhoneFlat: _isPhoneFlat,
      geomagneticRotationAzimuth: _geomagneticRotationAzimuth,
      gameRotationAzimuth: _gameRotationAzimuth,
    );

    final previousStepCount = _deadReckoningState.stepCount;
    _deadReckoningState = _deadReckoningCalculator.processSample(
      sample,
      _deadReckoningState,
    );
    _enqueueLogLine(
      sample,
      _deadReckoningState,
      imuStepDetected: _deadReckoningState.stepCount > previousStepCount,
    );
  }

  Future<void> _initializeLogging() async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'imu_log_$timestamp.csv';
      final directory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      await directory.create(recursive: true);
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(_csvHeader);

      if (!mounted) {
        return;
      }

      setState(() {
        _logFile = file;
      });

      _logFlushTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_flushPendingLogLines()),
      );
    } catch (error) {
      debugPrint('Log initialization failed: $error');
    }
  }

  void _enqueueLogLine(
    SensorSample sample,
    DeadReckoningState state, {
    required bool imuStepDetected,
  }) {
    final accelerometer = _accelerometerEvent;
    final userAccelerometer = _userAccelerometerEvent;
    final gyroscope = _gyroscopeEvent;
    final magnetometer = _magnetometerEvent;

    if (accelerometer == null ||
        userAccelerometer == null ||
        gyroscope == null ||
        magnetometer == null) {
      return;
    }

    final userAccelMagnitude = math.sqrt(
      userAccelerometer.x * userAccelerometer.x +
          userAccelerometer.y * userAccelerometer.y +
          userAccelerometer.z * userAccelerometer.z,
    );
    final gyroMagnitude = math.sqrt(
      gyroscope.x * gyroscope.x +
          gyroscope.y * gyroscope.y +
          gyroscope.z * gyroscope.z,
    );
    final tiltGyroMagnitude = math.sqrt(
      gyroscope.x * gyroscope.x + gyroscope.y * gyroscope.y,
    );
    final secondsSincePrevStep = state.lastStepTimestamp == null
        ? 0.0
        : sample.timestamp.difference(state.lastStepTimestamp!).inMilliseconds /
              1000.0;
    final headingChangeSincePrevStep = state.lastStepHeadingRadians == null
        ? 0.0
        : _headingDeltaDegrees(
            state.headingRadians,
            state.lastStepHeadingRadians!,
          );
    final headingChangeRateSincePrevStep = secondsSincePrevStep <= 1e-6
        ? 0.0
        : headingChangeSincePrevStep / secondsSincePrevStep;
    final recentStepIntervalMean = state.recentStepIntervals.isEmpty
        ? 0.0
        : state.recentStepIntervals.reduce((a, b) => a + b) /
              state.recentStepIntervals.length;
    final recentStepIntervalStd = _stddev(state.recentStepIntervals);
    final filteredToUserAccelRatio = userAccelMagnitude <= 0.05
        ? 0.0
        : state.filteredAccelerationMagnitude / userAccelMagnitude;
    final accelToGyroRatio = gyroMagnitude <= 0.05
        ? 0.0
        : userAccelMagnitude / gyroMagnitude;
    final fields = <String>[
      sample.timestamp.toIso8601String(),
      state.position.x.toStringAsFixed(6),
      state.position.y.toStringAsFixed(6),
      state.headingRadians.toStringAsFixed(6),
      _headingDegrees.toStringAsFixed(3),
      _headingLabel,
      state.stepCount.toString(),
      state.lastStepLengthMeters.toStringAsFixed(6),
      state.thresholdCrossings.toString(),
      state.totalDistanceMeters.toStringAsFixed(6),
      state.filteredAccelerationMagnitude.toStringAsFixed(6),
      state.activeStepThreshold.toStringAsFixed(6),
      _currentMotionMagnitude.toStringAsFixed(6),
      accelerometer.x.toStringAsFixed(6),
      accelerometer.y.toStringAsFixed(6),
      accelerometer.z.toStringAsFixed(6),
      userAccelerometer.x.toStringAsFixed(6),
      userAccelerometer.y.toStringAsFixed(6),
      userAccelerometer.z.toStringAsFixed(6),
      userAccelMagnitude.toStringAsFixed(6),
      gyroscope.x.toStringAsFixed(6),
      gyroscope.y.toStringAsFixed(6),
      gyroscope.z.toStringAsFixed(6),
      gyroMagnitude.toStringAsFixed(6),
      tiltGyroMagnitude.toStringAsFixed(6),
      magnetometer.x.toStringAsFixed(6),
      magnetometer.y.toStringAsFixed(6),
      magnetometer.z.toStringAsFixed(6),
      (_geomagneticRotationAzimuth ?? double.nan).toStringAsFixed(6),
      (_gameRotationAzimuth ?? double.nan).toStringAsFixed(6),
      (_activityRecognitionGranted ?? false).toString(),
      state.lastStepDecisionSource,
      state.lastStepDecisionConfidence.toStringAsFixed(6),
      secondsSincePrevStep.toStringAsFixed(6),
      headingChangeSincePrevStep.toStringAsFixed(6),
      headingChangeRateSincePrevStep.toStringAsFixed(6),
      recentStepIntervalMean.toStringAsFixed(6),
      recentStepIntervalStd.toStringAsFixed(6),
      filteredToUserAccelRatio.toStringAsFixed(6),
      accelToGyroRatio.toStringAsFixed(6),
      sample.isPhoneFlat.toString(),
      imuStepDetected.toString(),
    ];

    _pendingLogLines.add('${fields.join(',')}\n');
  }

  Future<void> _flushPendingLogLines() async {
    final file = _logFile;
    if (file == null || _pendingLogLines.isEmpty || _isFlushingLog) {
      return;
    }

    _isFlushingLog = true;
    final chunk = _pendingLogLines.join();
    _pendingLogLines.clear();

    try {
      await file.writeAsString(chunk, mode: FileMode.append, flush: true);
    } catch (error) {
      debugPrint('Log write failed: $error');
    } finally {
      _isFlushingLog = false;
    }
  }

  double get _currentMotionMagnitude {
    final event = _userAccelerometerEvent;
    if (event == null) {
      return 0;
    }

    return math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
  }

  double get _headingDegrees {
    final rawDegrees = _deadReckoningState.headingRadians * 180 / math.pi;
    return (90 - rawDegrees + 360) % 360;
  }

  double _headingDeltaDegrees(double a, double b) {
    final delta = (a - b).abs();
    final normalizedDelta = delta > math.pi ? (2 * math.pi) - delta : delta;
    return normalizedDelta * 180 / math.pi;
  }

  double _stddev(List<double> values) {
    if (values.length < 2) {
      return 0;
    }
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }

  String get _headingLabel {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = (((_headingDegrees + 22.5) % 360) / 45).floor();
    return labels[index];
  }

  @override
  void dispose() {
    _logFlushTimer?.cancel();
    unawaited(_flushPendingLogLines());
    _accelerometerSubscription?.cancel();
    _userAccelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _rotationVectorSubscription?.cancel();
    _dismissFlatPhoneDialog();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Indoor Navigation'),
        backgroundColor: RouteInPalette.navy,
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraView(),
          _buildTopGradient(),
          _buildBottomGradient(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [const Spacer(), _buildSensorOverlayCard(context)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (_cameraError != null) {
      return _CameraStatus(message: _cameraError!);
    }

    final controller = _cameraController;
    if (_cameraReady == null || controller == null) {
      return const _CameraStatus(message: 'Preparing camera...');
    }

    return FutureBuilder<void>(
      future: _cameraReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const _CameraStatus(message: 'Loading camera preview...');
        }

        return ColoredBox(
          color: RouteInPalette.ink,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewSize = controller.value.previewSize;
              if (previewSize == null) {
                return const _CameraStatus(
                  message: 'Camera preview unavailable.',
                );
              }

              final previewWidth = previewSize.height;
              final previewHeight = previewSize.width;
              final scale = math.max(
                constraints.maxWidth / previewWidth,
                constraints.maxHeight / previewHeight,
              );

              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: SizedBox(
                    width: previewWidth * scale,
                    height: previewHeight * scale,
                    child: CameraPreview(controller),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTopGradient() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 180,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [RouteInPalette.navy, RouteInPalette.denim],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomGradient() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 320,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [RouteInPalette.denim, RouteInPalette.navy],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSensorOverlayCard(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: RouteInPalette.navy,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: RouteInPalette.sky),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sensors_outlined,
                  color: RouteInPalette.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Sensor Feed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: RouteInPalette.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DeadReckoningStatus(
              positionX: _deadReckoningState.position.x,
              positionY: _deadReckoningState.position.y,
              stepCount: _deadReckoningState.stepCount,
              lastStepLengthMeters: _deadReckoningState.lastStepLengthMeters,
              recentStepIntervals: _deadReckoningState.recentStepIntervals,
              thresholdCrossings: _deadReckoningState.thresholdCrossings,
              totalDistanceMeters: _deadReckoningState.totalDistanceMeters,
              headingDegrees: _headingDegrees,
              headingLabel: _headingLabel,
              motionMagnitude: _currentMotionMagnitude,
              filteredAccelerationMagnitude:
                  _deadReckoningState.filteredAccelerationMagnitude,
              activeStepThreshold: _deadReckoningState.activeStepThreshold,
              stepDecisionSource: _deadReckoningState.lastStepDecisionSource,
              stepDecisionConfidence:
                  _deadReckoningState.lastStepDecisionConfidence,
              isPhoneFlat: _isPhoneFlat,
            ),
          ],
        ),
      ),
    );
  }
}

const String _csvHeader =
    'timestamp,position_x,position_y,heading_radians,heading_degrees,heading_label,steps,last_step_length_m,crossings,distance_m,filtered_accel,active_threshold,motion_magnitude,accel_x,accel_y,accel_z,user_accel_x,user_accel_y,user_accel_z,user_accel_magnitude,gyro_x,gyro_y,gyro_z,gyro_magnitude,tilt_gyro_magnitude,mag_x,mag_y,mag_z,geomagnetic_rotation_azimuth,game_rotation_azimuth,activity_recognition_granted,step_source,step_confidence,seconds_since_prev_step,heading_change_since_prev_step,heading_change_rate_since_prev_step,recent_step_interval_mean,recent_step_interval_std,filtered_to_user_accel_ratio,accel_to_gyro_ratio,phone_flat,imu_step_detected\n';

class _DeadReckoningStatus extends StatelessWidget {
  const _DeadReckoningStatus({
    required this.positionX,
    required this.positionY,
    required this.stepCount,
    required this.lastStepLengthMeters,
    required this.recentStepIntervals,
    required this.thresholdCrossings,
    required this.totalDistanceMeters,
    required this.headingDegrees,
    required this.headingLabel,
    required this.motionMagnitude,
    required this.filteredAccelerationMagnitude,
    required this.activeStepThreshold,
    required this.stepDecisionSource,
    required this.stepDecisionConfidence,
    required this.isPhoneFlat,
  });

  final double positionX;
  final double positionY;
  final int stepCount;
  final double lastStepLengthMeters;
  final List<double> recentStepIntervals;
  final int thresholdCrossings;
  final double totalDistanceMeters;
  final double headingDegrees;
  final String headingLabel;
  final double motionMagnitude;
  final double filteredAccelerationMagnitude;
  final double activeStepThreshold;
  final String stepDecisionSource;
  final double stepDecisionConfidence;
  final bool isPhoneFlat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recentFiveDuration = recentStepIntervals.fold<double>(
      0,
      (sum, interval) => sum + interval,
    );
    final recentFiveDurationText = recentStepIntervals.isEmpty
        ? 'Recent 5-step time: waiting for more steps'
        : 'Recent 5-step time: ${recentFiveDuration.toStringAsFixed(1)} s';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RouteInPalette.denim,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RouteInPalette.sky),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Transform.rotate(
                angle: (headingDegrees - 90) * math.pi / 180,
                child: const Icon(
                  Icons.navigation_rounded,
                  color: RouteInPalette.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Estimated Movement',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: RouteInPalette.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Current position: (${positionX.toStringAsFixed(2)}, ${positionY.toStringAsFixed(2)}) m',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RouteInPalette.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Direction: $headingLabel  ${headingDegrees.toStringAsFixed(0)} deg',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RouteInPalette.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isPhoneFlat ? 'Phone posture: flat' : 'Phone posture: upright',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isPhoneFlat ? RouteInPalette.coral : RouteInPalette.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Estimated distance: ${totalDistanceMeters.toStringAsFixed(2)} m',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RouteInPalette.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Current step length: ${lastStepLengthMeters.toStringAsFixed(2)} m',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RouteInPalette.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Axis: +x East, +y North   Steps: $stepCount   Crossings: $thresholdCrossings',
            style: theme.textTheme.bodySmall?.copyWith(
              color: RouteInPalette.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Motion: ${motionMagnitude.toStringAsFixed(2)}   Filtered: ${filteredAccelerationMagnitude.toStringAsFixed(2)}   Threshold: ${activeStepThreshold.toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: RouteInPalette.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Step judge: $stepDecisionSource ${(stepDecisionConfidence * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall?.copyWith(
              color: RouteInPalette.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            recentFiveDurationText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: RouteInPalette.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraStatus extends StatelessWidget {
  const _CameraStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(color: RouteInPalette.navy),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: RouteInPalette.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
