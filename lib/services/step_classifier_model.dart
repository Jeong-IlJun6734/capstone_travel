import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

class StepClassifierModel {
  StepClassifierModel({
    required this.featureNames,
    required this.weights,
    required this.bias,
    required this.decisionThreshold,
    required this.means,
    required this.stds,
  });

  factory StepClassifierModel.fromJson(Map<String, dynamic> json) {
    final normalization = json['normalization'] as Map<String, dynamic>;
    return StepClassifierModel(
      featureNames: List<String>.from(json['feature_names'] as List<dynamic>),
      weights: List<double>.from(
        (json['weights'] as List<dynamic>).map(
          (dynamic value) => (value as num).toDouble(),
        ),
      ),
      bias: (json['bias'] as num).toDouble(),
      decisionThreshold: (json['decision_threshold'] as num).toDouble(),
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
    );
  }

  static Future<StepClassifierModel> loadAsset(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    return StepClassifierModel.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  final List<String> featureNames;
  final List<double> weights;
  final double bias;
  final double decisionThreshold;
  final List<double> means;
  final List<double> stds;

  double predictProbability(List<double> features) {
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

    return _sigmoid(score);
  }

  bool classify(List<double> features) {
    return predictProbability(features) >= decisionThreshold;
  }

  double _sigmoid(double value) {
    if (value >= 0) {
      final expValue = math.exp(-value);
      return 1 / (1 + expValue);
    }
    final expValue = math.exp(value);
    return expValue / (1 + expValue);
  }
}
