import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../services/dead_reckoning_calculator.dart';
import '../services/indoor_qr_position_service.dart';
import '../services/indoor_route_service.dart';
import '../services/naver_map_config.dart';
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
  static const Duration _qrScanInterval = Duration(milliseconds: 450);
  static const double _preferredQrZoomLevel = 1.4;
  static const Duration _qrCorrectionCooldown = Duration(seconds: 3);
  static const Duration _mapSyncInterval = Duration(milliseconds: 700);
  static const double _indoorMetersPerImagePixel = 0.057;
  static const double _indoorImagePixelsPerMeter =
      1 / _indoorMetersPerImagePixel;
  static const NLatLng _soongsilStationPosition = NLatLng(37.49611, 126.95389);
  static const String _defaultIndoorRouteLine = '7';
  static const String _defaultIndoorRouteStation =
      '\uC22D\uC2E4\uB300\uC785\uAD6C';
  static const String _defaultIndoorRouteStartNode = 'node_003';
  static const String _defaultIndoorRouteEndNode = 'node_050';

  final DeadReckoningCalculator _deadReckoningCalculator =
      DeadReckoningCalculator(
        config: const DeadReckoningConfig(
          positionUnitsPerMeter: _indoorImagePixelsPerMeter,
        ),
      );
  final IndoorQrPositionService _qrPositionService = IndoorQrPositionService();
  final IndoorRouteService _routeService = IndoorRouteService();
  final BarcodeScanner _qrScanner = BarcodeScanner(
    formats: [BarcodeFormat.qrCode],
  );
  final List<String> _pendingLogLines = <String>[];

  CameraController? _cameraController;
  Future<void>? _cameraReady;
  NaverMapController? _indoorMapController;
  NMarker? _currentIndoorPositionMarker;
  IndoorRoute? _indoorRoute;
  IndoorRouteNode? _activeRouteNode;

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
  bool _isProcessingQrFrame = false;
  bool _isResolvingQrPosition = false;
  bool _isCameraPreviewActive = false;
  bool _hasStartedIndoorMapTracking = false;
  bool _canShowIndoorMap = false;
  bool _isLoadingIndoorRoute = false;
  bool _hasStartedPdr = false;
  int _flatPhoneEnterStreak = 0;
  int _flatPhoneExitStreak = 0;
  DateTime? _lastQrScanStartedAt;
  DateTime? _lastQrCorrectionAt;
  DateTime? _lastMapSyncAt;
  String? _lastCorrectedQrValue;
  String _routeStatusMessage = 'Route: waiting';

  @override
  void initState() {
    super.initState();
    unawaited(_initializePage());
  }

  Future<void> _initializePage() async {
    await _loadSelfSupervisedStepModel();
    await _requestPermissions();
    if (!mounted) {
      return;
    }

    final cameraReady = _initializeCamera();
    setState(() {
      _cameraReady = cameraReady;
    });

    await cameraReady;
    if (!mounted || _cameraController == null || _cameraError != null) {
      return;
    }

    setState(() {
      _canShowIndoorMap = true;
    });
    unawaited(_loadDefaultIndoorRoute());
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

  Future<void> _loadDefaultIndoorRoute() async {
    if (_isLoadingIndoorRoute) {
      return;
    }

    setState(() {
      _isLoadingIndoorRoute = true;
      _routeStatusMessage = 'Route: loading';
    });

    try {
      final route = await _routeService.fetchRoute(
        line: _defaultIndoorRouteLine,
        station: _defaultIndoorRouteStation,
        startNodeId: _defaultIndoorRouteStartNode,
        endNodeId: _defaultIndoorRouteEndNode,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _indoorRoute = route;
        _activeRouteNode = route.nextNodeFrom(_deadReckoningState.position);
        _routeStatusMessage = 'Route: ${route.nodes.length} nodes';
      });
    } catch (error) {
      _reportDebugIssue('Indoor route request failed: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _routeStatusMessage = 'Route: failed';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingIndoorRoute = false;
        });
      } else {
        _isLoadingIndoorRoute = false;
      }
    }
  }

  Future<void> _requestPermissions() async {
    _updateDebugStatus(camera: 'Camera: requesting permission');
    final cameraStatus = await Permission.camera.request();

    _updateDebugStatus(map: 'Map: requesting location permission');
    await Permission.locationWhenInUse.request();

    _updateDebugStatus(pdr: 'PDR: requesting activity permission');
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
      _updateDebugStatus(camera: 'Camera: finding cameras');
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setCameraError('No camera available on this device.');
        return;
      }

      _updateDebugStatus(camera: 'Camera: initializing preview');
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : null,
      );

      await controller.initialize();
      await _configureQrCamera(controller);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraError = null;
        _isCameraPreviewActive = true;
        _hasShownCameraErrorDialog = false;
      });
      unawaited(_startQrImageStream(controller));
    } catch (error) {
      if (!mounted) {
        return;
      }

      _setCameraError('Camera initialization failed: $error');
    }
  }

  Future<void> _startQrImageStream(CameraController controller) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _updateDebugStatus(qr: 'QR: stream unsupported on this platform');
      return;
    }

    if (!controller.value.isInitialized || controller.value.isStreamingImages) {
      return;
    }

    try {
      await controller.startImageStream(_handleCameraImage);
      _updateDebugStatus(qr: 'QR: scanning');
    } catch (error) {
      _reportDebugIssue('QR image stream unavailable: $error', qr: true);
    }
  }

  Future<void> _configureQrCamera(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (error) {
      debugPrint('Camera focus mode setup skipped: $error');
    }

    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (error) {
      debugPrint('Camera exposure mode setup skipped: $error');
    }

    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final zoom = _preferredQrZoomLevel.clamp(minZoom, maxZoom).toDouble();
      await controller.setZoomLevel(zoom);
    } catch (error) {
      debugPrint('Camera zoom setup skipped: $error');
    }
  }

  void _handleCameraImage(CameraImage image) {
    if (_isProcessingQrFrame) {
      return;
    }

    final now = DateTime.now();
    final lastScan = _lastQrScanStartedAt;
    if (lastScan != null && now.difference(lastScan) < _qrScanInterval) {
      return;
    }

    _lastQrScanStartedAt = now;
    _isProcessingQrFrame = true;
    unawaited(_processQrFrame(image));
  }

  Future<void> _processQrFrame(CameraImage image) async {
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        return;
      }

      final barcodes = await _qrScanner.processImage(inputImage);
      for (final barcode in barcodes) {
        final qrValue = barcode.rawValue;
        if (qrValue == null || qrValue.isEmpty) {
          continue;
        }

        await _resolveQrPosition(qrValue);
        break;
      }
    } catch (error) {
      _reportDebugIssue('QR scan failed: $error', qr: true);
    } finally {
      _isProcessingQrFrame = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _cameraController;
    if (controller == null || image.planes.isEmpty) {
      return null;
    }

    final inputFormat = _inputImageFormatFor(image.format.group);
    final rotation = InputImageRotationValue.fromRawValue(
      controller.description.sensorOrientation,
    );

    if (inputFormat == null || rotation == null) {
      return null;
    }

    final bytes = _cameraImageBytes(image);
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: inputFormat,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  InputImageFormat? _inputImageFormatFor(ImageFormatGroup formatGroup) {
    switch (formatGroup) {
      case ImageFormatGroup.nv21:
        return InputImageFormat.nv21;
      case ImageFormatGroup.yuv420:
        return Platform.isIOS ? InputImageFormat.yuv420 : null;
      case ImageFormatGroup.bgra8888:
        return InputImageFormat.bgra8888;
      case ImageFormatGroup.jpeg:
      case ImageFormatGroup.unknown:
        return null;
    }
  }

  Uint8List _cameraImageBytes(CameraImage image) {
    if (image.planes.length == 1) {
      return image.planes.first.bytes;
    }

    final buffer = WriteBuffer();
    for (final plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    return buffer.done().buffer.asUint8List();
  }

  Future<void> _resolveQrPosition(String qrValue) async {
    final now = DateTime.now();
    final isSameRecentQr =
        _lastCorrectedQrValue == qrValue &&
        _lastQrCorrectionAt != null &&
        now.difference(_lastQrCorrectionAt!) < _qrCorrectionCooldown;

    if (_isResolvingQrPosition || isSameRecentQr) {
      return;
    }

    _isResolvingQrPosition = true;

    try {
      final correction = await _qrPositionService.resolveQrPosition(qrValue);
      if (!mounted) {
        return;
      }

      setState(() {
        _deadReckoningState = _deadReckoningState.copyWith(
          position: vm.Vector2(correction.x, correction.y),
        );
        _activeRouteNode = _indoorRoute?.nextNodeFrom(
          _deadReckoningState.position,
        );
        _lastCorrectedQrValue = qrValue;
        _lastQrCorrectionAt = correction.resolvedAt;
      });
      _syncIndoorMapLocation(forceCamera: true);
    } catch (error) {
      _reportDebugIssue('QR position request failed: $error', qr: true);
    } finally {
      _isResolvingQrPosition = false;
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

  void _reportDebugIssue(String message, {bool qr = false, bool map = false}) {
    final source = qr
        ? 'QR'
        : map
        ? 'Map'
        : 'Debug';
    debugPrint('$source: $message');
  }

  void _updateDebugStatus({
    String? camera,
    String? qr,
    String? map,
    String? pdr,
  }) {
    final messages = [camera, qr, map, pdr].whereType<String>().join(' ');
    if (messages.isNotEmpty) {
      debugPrint(messages);
    }
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
    _activeRouteNode = _indoorRoute?.nextNodeFrom(_deadReckoningState.position);
    _scheduleIndoorMapSync();
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

  double _normalizeRadians(double angle) {
    return ((angle + math.pi) % (2 * math.pi)) - math.pi;
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

  void _rememberIndoorMapController(NaverMapController controller) {
    _indoorMapController = controller;
    _updateDebugStatus(map: 'Map: ready');
    _syncIndoorMapLocation();
    _startIndoorMapLocationTracking();
    _startPdr();
  }

  void _startIndoorMapLocationTracking() {
    final controller = _indoorMapController;
    if (controller == null ||
        !_isCameraPreviewActive ||
        _hasStartedIndoorMapTracking) {
      return;
    }

    _hasStartedIndoorMapTracking = true;
    controller.setLocationTrackingMode(NLocationTrackingMode.face);
    _updateDebugStatus(map: 'Map: location tracking enabled');
  }

  void _startPdr() {
    if (_hasStartedPdr) {
      return;
    }

    _hasStartedPdr = true;
    _startSensorStreams();
    _startRotationVectorStream();
    unawaited(_initializeLogging());
    _updateDebugStatus(pdr: 'PDR: active');
  }

  void _scheduleIndoorMapSync() {
    final now = DateTime.now();
    final lastSync = _lastMapSyncAt;
    if (lastSync != null && now.difference(lastSync) < _mapSyncInterval) {
      return;
    }

    _lastMapSyncAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncIndoorMapLocation();
      }
    });
  }

  void _syncIndoorMapLocation({bool forceCamera = false}) {
    final controller = _indoorMapController;
    if (controller == null || !NaverMapConfig.isReady) {
      return;
    }

    final mapPosition = _indoorMetersToLatLng(_deadReckoningState.position);
    final marker = _currentIndoorPositionMarker;
    if (marker == null) {
      final nextMarker = NMarker(
        id: 'current_indoor_position',
        position: mapPosition,
        iconTintColor: RouteInPalette.coral,
        caption: const NOverlayCaption(text: 'Current position'),
      );
      _currentIndoorPositionMarker = nextMarker;
      unawaited(controller.addOverlay(nextMarker));
    } else {
      marker.setPosition(mapPosition);
    }

    final locationOverlay = controller.getLocationOverlay();
    locationOverlay.setBearing(_headingDegrees);

    if (forceCamera) {
      unawaited(
        controller.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: mapPosition, zoom: 17),
        ),
      );
    }
  }

  NLatLng _indoorMetersToLatLng(vm.Vector2 position) {
    const metersPerLatitudeDegree = 111320.0;
    final positionMeters = position * _indoorMetersPerImagePixel;
    final latitude =
        _soongsilStationPosition.latitude +
        (positionMeters.y / metersPerLatitudeDegree);
    final longitudeMetersPerDegree =
        metersPerLatitudeDegree *
        math.cos(_soongsilStationPosition.latitude * math.pi / 180);
    final longitude =
        _soongsilStationPosition.longitude +
        (positionMeters.x / longitudeMetersPerDegree);
    return NLatLng(latitude, longitude);
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
    final cameraController = _cameraController;
    if (cameraController != null) {
      if (cameraController.value.isStreamingImages) {
        unawaited(
          cameraController
              .stopImageStream()
              .catchError((Object error) {
                debugPrint('Camera image stream stop failed: $error');
              })
              .whenComplete(cameraController.dispose),
        );
      } else {
        unawaited(cameraController.dispose());
      }
    }
    unawaited(_qrScanner.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor Navigation'),
        backgroundColor: RouteInPalette.navy,
        elevation: 0,
      ),
      backgroundColor: RouteInPalette.ink,
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCameraView(),
                _buildTopGradient(),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _buildNavigationSummary(context),
                    ),
                  ),
                ),
                Positioned.fill(child: _buildArRouteOverlay(context)),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height / 3,
            width: double.infinity,
            child: _buildIndoorMapPanel(context),
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

  Widget _buildArRouteOverlay(BuildContext context) {
    final route = _indoorRoute;
    final target = _activeRouteNode;
    if (route == null || target == null) {
      return Align(
        alignment: Alignment.center,
        child: _ArRouteStatus(
          message: _isLoadingIndoorRoute ? '경로 불러오는 중' : _routeStatusMessage,
          onRetry: _isLoadingIndoorRoute ? null : _loadDefaultIndoorRoute,
        ),
      );
    }

    final currentPosition = _deadReckoningState.position;
    final vectorToTarget = target.position - currentPosition;
    final distance = vectorToTarget.length;
    final distanceMeters = distance * _indoorMetersPerImagePixel;
    final routeAngle = math.atan2(vectorToTarget.y, vectorToTarget.x);
    final relativeAngle = _normalizeRadians(
      routeAngle - _deadReckoningState.headingRadians,
    );
    final arrowSize = (56 + distance / 6).clamp(56, 132).toDouble();
    final targetIndex = route.nodes.indexWhere((node) => node.id == target.id);
    final stepText = targetIndex < 0
        ? '-'
        : '${targetIndex + 1}/${route.nodes.length}';
    final segment = route.segmentToNode(target.id);
    final guidanceText = _routeGuidanceText(target, segment);

    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RouteInPalette.ink.withValues(alpha: 0.34),
                  boxShadow: [
                    BoxShadow(
                      color: RouteInPalette.ink.withValues(alpha: 0.46),
                      blurRadius: 28,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Transform.rotate(
                    angle: relativeAngle,
                    child: Icon(
                      Icons.navigation_rounded,
                      color: RouteInPalette.white,
                      size: arrowSize,
                      shadows: const [
                        Shadow(color: RouteInPalette.ink, blurRadius: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: RouteInPalette.ink.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: RouteInPalette.sky),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$stepText · ${target.floor} · ${distanceMeters.toStringAsFixed(1)} m',
                        style: const TextStyle(
                          color: RouteInPalette.sky,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (guidanceText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          guidanceText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: RouteInPalette.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _routeGuidanceText(
    IndoorRouteNode target,
    IndoorRouteSegment? segment,
  ) {
    if (target.isElevatorBoardingNode) {
      return '엘리베이터 탑승 지점';
    }
    if (target.isElevatorPassingNode || target.isElevatorNode) {
      return '엘리베이터 이동 중';
    }
    if (segment == null) {
      return '';
    }

    final floorChange =
        segment.fromFloor.isNotEmpty &&
        segment.toFloor.isNotEmpty &&
        segment.fromFloor != segment.toFloor;
    final distance = segment.distance > 0
        ? ' · ${(segment.distance * _indoorMetersPerImagePixel).toStringAsFixed(1)} m'
        : '';

    if (segment.usesElevator) {
      return '엘리베이터 ${segment.fromFloor} → ${segment.toFloor}$distance';
    }
    if (floorChange) {
      return '층 이동 ${segment.fromFloor} → ${segment.toFloor}$distance';
    }
    if (segment.kind.isNotEmpty && segment.kind != 'walk') {
      return '${segment.kind}$distance';
    }
    return '직진$distance';
  }

  Widget _buildIndoorMapPanel(BuildContext context) {
    if (!_canShowIndoorMap) {
      return const _IndoorMapUnavailableState(
        icon: Icons.map_outlined,
        title: 'Map waiting',
        description: 'Camera preview starts before indoor map loading.',
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: RouteInPalette.mist),
      child: !NaverMapConfig.supportsMobileMap
          ? const _IndoorMapUnavailableState(
              icon: Icons.phone_android_rounded,
              title: 'Mobile map only',
              description: 'Indoor position map is available on Android/iOS.',
            )
          : !NaverMapConfig.hasClientId
          ? const _IndoorMapUnavailableState(
              icon: Icons.key_rounded,
              title: 'Map key required',
              description: 'Add a Naver Map client ID to show your position.',
            )
          : !NaverMapConfig.isReady
          ? const _IndoorMapUnavailableState(
              icon: Icons.map_outlined,
              title: 'Preparing map',
              description: 'Naver Map is still initializing.',
            )
          : NaverMap(
              options: const NaverMapViewOptions(
                mapType: NMapType.basic,
                locationButtonEnable: true,
                initialCameraPosition: NCameraPosition(
                  target: _soongsilStationPosition,
                  zoom: 17,
                ),
              ),
              onMapReady: _rememberIndoorMapController,
            ),
    );
  }

  Widget _buildNavigationSummary(BuildContext context) {
    final positionMeters =
        _deadReckoningState.position * _indoorMetersPerImagePixel;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: RouteInPalette.navy.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RouteInPalette.sky),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                icon: Transform.rotate(
                  angle: (_headingDegrees - 90) * math.pi / 180,
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: RouteInPalette.white,
                    size: 20,
                  ),
                ),
                label: 'Direction',
                value: '$_headingLabel ${_headingDegrees.toStringAsFixed(0)}°',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryMetric(
                icon: const Icon(
                  Icons.directions_walk_rounded,
                  color: RouteInPalette.white,
                  size: 20,
                ),
                label: 'Steps',
                value: _deadReckoningState.stepCount.toString(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryMetric(
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: RouteInPalette.white,
                  size: 20,
                ),
                label: 'Position',
                value:
                    '${positionMeters.x.toStringAsFixed(1)}, '
                    '${positionMeters.y.toStringAsFixed(1)} m',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const String _csvHeader =
    'timestamp,position_x,position_y,heading_radians,heading_degrees,heading_label,steps,last_step_length_m,crossings,distance_m,filtered_accel,active_threshold,motion_magnitude,accel_x,accel_y,accel_z,user_accel_x,user_accel_y,user_accel_z,user_accel_magnitude,gyro_x,gyro_y,gyro_z,gyro_magnitude,tilt_gyro_magnitude,mag_x,mag_y,mag_z,geomagnetic_rotation_azimuth,game_rotation_azimuth,activity_recognition_granted,step_source,step_confidence,seconds_since_prev_step,heading_change_since_prev_step,heading_change_rate_since_prev_step,recent_step_interval_mean,recent_step_interval_std,filtered_to_user_accel_ratio,accel_to_gyro_ratio,phone_flat,imu_step_detected\n';

class _ArRouteStatus extends StatelessWidget {
  const _ArRouteStatus({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RouteInPalette.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RouteInPalette.sky),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.route_rounded,
              color: RouteInPalette.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              message,
              style: const TextStyle(
                color: RouteInPalette.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Retry',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                color: RouteInPalette.sky,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final Widget icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            icon,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: RouteInPalette.sky,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: RouteInPalette.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _IndoorMapUnavailableState extends StatelessWidget {
  const _IndoorMapUnavailableState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: RouteInPalette.navy, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: RouteInPalette.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: RouteInPalette.navy,
              ),
            ),
          ],
        ),
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
