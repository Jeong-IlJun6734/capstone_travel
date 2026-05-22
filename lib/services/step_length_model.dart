import 'dart:convert';

import 'package:flutter/services.dart';

class StepLengthModel {
  StepLengthModel({
    required this.featureNames,
    required this.weights,
    required this.bias,
    required this.means,
    required this.stds,
    required this.minimumStepLengthMeters,
    required this.maximumStepLengthMeters,
  });

  factory StepLengthModel.fromJson(Map<String, dynamic> json) {
    final normalization = json['normalization'] as Map<String, dynamic>;
    return StepLengthModel(
      featureNames: List<String>.from(json['feature_names'] as List<dynamic>),
      weights: List<double>.from(
        (json['weights'] as List<dynamic>).map(
          (dynamic value) => (value as num).toDouble(),
        ),
      ),
      bias: (json['bias'] as num).toDouble(),
      means: List<double>.from(
        (normalization['means'] as List<dynamic>).map(
          (dynamic value) => (value as num).toDouble(),
        ),
      ),
      stds: List<double>.from(
        (normalization['stds'] as List<dynamic>).map(
          (dynamic value) => (value as num).toDouble(),
        ),
      ),
      minimumStepLengthMeters:
          (json['minimum_step_length_meters'] as num).toDouble(),
      maximumStepLengthMeters:
          (json['maximum_step_length_meters'] as num).toDouble(),
    );
  }

  static Future<StepLengthModel> loadAsset(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    return StepLengthModel.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  final List<String> featureNames;
  final List<double> weights;
  final double bias;
  final List<double> means;
  final List<double> stds;
  final double minimumStepLengthMeters;
  final double maximumStepLengthMeters;

  double predictMeters(List<double> features) {
    if (features.length != weights.length ||
        features.length != means.length ||
        features.length != stds.length) {
      throw ArgumentError(
        'Feature length ${features.length} does not match model length ${weights.length}.',
      );
    }

    var score = bias;
    for (var i = 0; i < features.length; i += 1) {
      final normalized = (features[i] - means[i]) / stds[i];
      score += weights[i] * normalized;
    }

    return score
        .clamp(minimumStepLengthMeters, maximumStepLengthMeters)
        .toDouble();
  }
}
