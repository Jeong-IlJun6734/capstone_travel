import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

class SelfSupervisedStepModel {
  SelfSupervisedStepModel({
    required this.featureNames,
    required this.means,
    required this.stds,
    required this.featureWeights,
    required this.centroids,
    required this.stepDecisionThreshold,
    required this.stepClusterIndex,
    required this.stepClusterIndices,
    required this.minimumStepLengthMeters,
    required this.maximumStepLengthMeters,
    required this.lengthWeights,
    required this.lengthBias,
  });

  factory SelfSupervisedStepModel.fromJson(Map<String, dynamic> json) {
    final normalization = json['normalization'] as Map<String, dynamic>;
    final clusters = json['clusters'] as List<dynamic>;
    return SelfSupervisedStepModel(
      featureNames: List<String>.from(json['feature_names'] as List<dynamic>),
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
      featureWeights: List<double>.from(
        ((json['feature_weights'] as List<dynamic>?) ??
                List<double>.filled(
                  (json['feature_names'] as List<dynamic>).length,
                  1,
                ))
            .map((dynamic value) => (value as num).toDouble()),
      ),
      centroids: clusters
          .map(
            (dynamic cluster) => List<double>.from(
              (cluster as Map<String, dynamic>)['centroid'] as List<dynamic>,
            ).map((dynamic value) => (value as num).toDouble()).toList(),
          )
          .toList(),
      stepDecisionThreshold: (json['step_decision_threshold'] as num)
          .toDouble(),
      stepClusterIndex: (json['step_cluster_index'] as num).toInt(),
      stepClusterIndices: List<int>.from(
        ((json['step_cluster_indices'] as List<dynamic>?) ??
                <dynamic>[json['step_cluster_index']])
            .map((dynamic value) => (value as num).toInt()),
      ),
      minimumStepLengthMeters: (json['minimum_step_length_meters'] as num)
          .toDouble(),
      maximumStepLengthMeters: (json['maximum_step_length_meters'] as num)
          .toDouble(),
      lengthWeights: List<double>.from(
        (json['length_weights'] as List<dynamic>).map(
          (dynamic value) => (value as num).toDouble(),
        ),
      ),
      lengthBias: (json['length_bias'] as num).toDouble(),
    );
  }

  static Future<SelfSupervisedStepModel> loadAsset(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    return SelfSupervisedStepModel.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  final List<String> featureNames;
  final List<double> means;
  final List<double> stds;
  final List<double> featureWeights;
  final List<List<double>> centroids;
  final double stepDecisionThreshold;
  final int stepClusterIndex;
  final List<int> stepClusterIndices;
  final double minimumStepLengthMeters;
  final double maximumStepLengthMeters;
  final List<double> lengthWeights;
  final double lengthBias;

  double stepProbability(List<double> features) {
    final normalized = _weightedNormalize(features);
    final distances = centroids
        .map((centroid) => _distance(normalized, centroid))
        .toList();
    final maxScore = distances.map((distance) => -distance).reduce(math.max);
    final expScores = distances
        .map((distance) => math.exp((-distance) - maxScore))
        .toList();
    final total = expScores.fold<double>(0, (sum, value) => sum + value);
    if (total <= 1e-9) {
      return 0.5;
    }
    var selectedScore = 0.0;
    for (final index in stepClusterIndices) {
      selectedScore += expScores[index];
    }
    return selectedScore / total;
  }

  bool classifyStep(List<double> features) {
    return stepProbability(features) >= stepDecisionThreshold;
  }

  double predictStepLengthMeters(List<double> features) {
    final normalized = _normalize(features);
    final linearScore = lengthBias + _dot(lengthWeights, normalized);
    final confidence = stepProbability(features);
    final adjusted = linearScore + (confidence - 0.5) * 0.04;
    return adjusted
        .clamp(minimumStepLengthMeters, maximumStepLengthMeters)
        .toDouble();
  }

  List<double> _normalize(List<double> features) {
    if (features.length != means.length || features.length != stds.length) {
      throw ArgumentError(
        'Feature length ${features.length} does not match model length ${means.length}.',
      );
    }
    return [
      for (var i = 0; i < features.length; i += 1)
        (features[i] - means[i]) / stds[i],
    ];
  }

  List<double> _weightedNormalize(List<double> features) {
    final normalized = _normalize(features);
    if (featureWeights.length != normalized.length) {
      throw ArgumentError(
        'Feature weight length ${featureWeights.length} does not match model length ${normalized.length}.',
      );
    }
    return [
      for (var i = 0; i < normalized.length; i += 1)
        normalized[i] * featureWeights[i],
    ];
  }

  double _distance(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i += 1) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  double _dot(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i += 1) {
      sum += a[i] * b[i];
    }
    return sum;
  }
}
