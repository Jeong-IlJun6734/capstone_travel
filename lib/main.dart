import 'package:flutter/material.dart';

import 'app.dart';
import 'services/naver_map_config.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NaverMapConfig.initialize();
  runApp(const RouteInApp());
}
