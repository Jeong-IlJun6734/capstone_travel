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
import '../services/step_classifier_model.dart';

class IndoorNavigationPage extends StatefulWidget {
  const IndoorNavigationPage({super.key});

  @override
  State<IndoorNavigationPage> createState() => _IndoorNavigationPageState();
}

class _IndoorNavigationPageState extends State<IndoorNavigationPage> {
  static const EventChannel _rotationVectorChannel = EventChannel(
    'demo_app/rotation_vectors',
  );
  static const EventChannel _stepDetectorChannel = EventChannel(
    'demo_app/step_detector',
  );

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
  StreamSubscription<dynamic>? _stepDetectorSubscription;

  AccelerometerEvent? _accelerometerEvent;
  UserAccelerometerEvent? _userAccelerometerEvent;
  GyroscopeEvent? _gyroscopeEvent;
  MagnetometerEvent? _magnetometerEvent;
  double? _geomagneticRotationAzimuth;
  double? _gameRotationAzimuth;
  bool? _cameraPermissionGranted;
  bool? _activityRecognitionGranted;
  bool _stepDetectorAvailable = false;
  int _stepDetectorEventCount = 0;
  DateTime? _lastStepDetectorEventAt;
  bool _pendingHardwareStepDetected = false;
  DeadReckoningState _deadReckoningState = DeadReckoningState.initial();
  Timer? _logFlushTimer;
  File? _logFile;
  String? _cameraError;
  bool _hasShownCameraErrorDialog = false;
  bool _isFlushingLog = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializePage());
  }

  Future<void> _initializePage() async {
    await _loadStepClassifierModel();
    await _requestPermissions();
    _cameraReady = _initializeCamera();
    _startSensorStreams();
    _startRotationVectorStream();
    _startStepDetectorStream();
    await _initializeLogging();
  }

  Future<void> _loadStepClassifierModel() async {
    try {
      final model = await StepClassifierModel.loadAsset(
        'models/step_classifier.json',
      );
      _deadReckoningCalculator.setStepClassifierModel(model);
    } catch (_) {
      _deadReckoningCalculator.setStepClassifierModel(null);
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

  void _startSensorStreams() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _accelerometerEvent = event;
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

  void _startStepDetectorStream() {
    _stepDetectorSubscription = _stepDetectorChannel
        .receiveBroadcastStream()
        .listen((dynamic event) {
          if (!mounted || event is! Map<Object?, Object?>) {
            return;
          }

          final available = event['available'] == true;
          final stepDetected = event['stepDetected'] == true;

          setState(() {
            _stepDetectorAvailable = available;
            if (stepDetected) {
              _stepDetectorEventCount += 1;
              _lastStepDetectorEventAt = DateTime.now();
              _pendingHardwareStepDetected = true;
            }
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
    final hardwareStepDetected = _pendingHardwareStepDetected;
    _pendingHardwareStepDetected = false;

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
      hardwareStepDetected: hardwareStepDetected,
      preferHardwareStepDetector: false,
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
    final hardwareStepGatePassed =
        userAccelMagnitude >= 0.4 &&
        userAccelMagnitude <= 3.6 &&
        gyroMagnitude <= 2.5;

    final fields = <String>[
      sample.timestamp.toIso8601String(),
      state.position.x.toStringAsFixed(6),
      state.position.y.toStringAsFixed(6),
      state.headingRadians.toStringAsFixed(6),
      _headingDegrees.toStringAsFixed(3),
      _headingLabel,
      state.stepCount.toString(),
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
      _stepDetectorAvailable.toString(),
      _stepDetectorEventCount.toString(),
      _lastStepDetectorEventAt?.toIso8601String() ?? '',
      (_activityRecognitionGranted ?? false).toString(),
      'false',
      _stepDetectorStatus,
      'IMU_LINEAR_ACCELERATION',
      sample.hardwareStepDetected.toString(),
      hardwareStepGatePassed.toString(),
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

  String get _headingLabel {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = (((_headingDegrees + 22.5) % 360) / 45).floor();
    return labels[index];
  }

  String get _stepDetectorStatus {
    if (_activityRecognitionGranted == false) {
      return 'permission_denied';
    }
    if (!_stepDetectorAvailable) {
      return 'unavailable';
    }
    if (_stepDetectorEventCount == 0) {
      return 'waiting_first_event';
    }
    return 'active';
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
    _stepDetectorSubscription?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Indoor Navigation'),
        backgroundColor: Colors.transparent,
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
          color: Colors.black,
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
              colors: [Color(0xA6000000), Color(0x00000000)],
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
              colors: [Color(0x00000000), Color(0xCC000000)],
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
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
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
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Sensor Feed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
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
              recentStepIntervals: _deadReckoningState.recentStepIntervals,
              thresholdCrossings: _deadReckoningState.thresholdCrossings,
              totalDistanceMeters: _deadReckoningState.totalDistanceMeters,
              headingDegrees: _headingDegrees,
              headingLabel: _headingLabel,
              motionMagnitude: _currentMotionMagnitude,
              filteredAccelerationMagnitude:
                  _deadReckoningState.filteredAccelerationMagnitude,
              activeStepThreshold: _deadReckoningState.activeStepThreshold,
            ),
          ],
        ),
      ),
    );
  }
}

const String _csvHeader =
    'timestamp,position_x,position_y,heading_radians,heading_degrees,heading_label,steps,crossings,distance_m,filtered_accel,active_threshold,motion_magnitude,accel_x,accel_y,accel_z,user_accel_x,user_accel_y,user_accel_z,user_accel_magnitude,gyro_x,gyro_y,gyro_z,gyro_magnitude,tilt_gyro_magnitude,mag_x,mag_y,mag_z,geomagnetic_rotation_azimuth,game_rotation_azimuth,step_detector_available,step_detector_event_count,last_step_detector_event_at,activity_recognition_granted,prefer_hardware_step_detector,step_detector_status,step_source,hardware_step_detected,hardware_step_gate_passed,imu_step_detected\n';

class _DeadReckoningStatus extends StatelessWidget {
  const _DeadReckoningStatus({
    required this.positionX,
    required this.positionY,
    required this.stepCount,
    required this.recentStepIntervals,
    required this.thresholdCrossings,
    required this.totalDistanceMeters,
    required this.headingDegrees,
    required this.headingLabel,
    required this.motionMagnitude,
    required this.filteredAccelerationMagnitude,
    required this.activeStepThreshold,
  });

  final double positionX;
  final double positionY;
  final int stepCount;
  final List<double> recentStepIntervals;
  final int thresholdCrossings;
  final double totalDistanceMeters;
  final double headingDegrees;
  final String headingLabel;
  final double motionMagnitude;
  final double filteredAccelerationMagnitude;
  final double activeStepThreshold;

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
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
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
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Estimated Movement',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Current position: (${positionX.toStringAsFixed(2)}, ${positionY.toStringAsFixed(2)}) m',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Direction: $headingLabel  ${headingDegrees.toStringAsFixed(0)} deg',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Estimated distance: ${totalDistanceMeters.toStringAsFixed(2)} m',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Axis: +x East, +y North   Steps: $stepCount   Crossings: $thresholdCrossings',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            'Motion: ${motionMagnitude.toStringAsFixed(2)}   Filtered: ${filteredAccelerationMagnitude.toStringAsFixed(2)}   Threshold: ${activeStepThreshold.toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            recentFiveDurationText,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
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
      decoration: const BoxDecoration(color: Color(0xFF1B1B1B)),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
