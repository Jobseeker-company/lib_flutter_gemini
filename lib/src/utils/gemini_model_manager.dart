import 'dart:developer';

import 'package:flutter_gemini/src/config/constants.dart';
import 'package:flutter_gemini/src/init.dart';
import 'package:flutter_gemini/src/models/gemini_model/gemini_model.dart';

import '../implement/gemini_service.dart';

class GeminiModelManager {
  final GeminiService _api;
  List<GeminiModel>? _models;

  GeminiModelManager(this._api);

  Future<String> resolveModelName({
    required String? userModel,
    String? defaultModel,
    required String expectedModel,
  }) async {
    final effectiveModel = (userModel != null && userModel.trim().isNotEmpty)
        ? userModel.trim()
        : (defaultModel != null && defaultModel.trim().isNotEmpty)
            ? defaultModel.trim()
            : null;

    if (Gemini.instance.disableAutoUpdateModelName) {
      return effectiveModel ?? expectedModel;
    }

    try {
      _models ??= await _listModels();
    } catch (_) {
      // If model listing fails, fallback directly to effectiveModel or expectedModel
      return effectiveModel ?? expectedModel;
    }

    if (effectiveModel != null) {
      final resolved = _findModel(effectiveModel);
      if (resolved != null) return resolved;
      _logModelNotFound(effectiveModel);
    }

    final resolvedExpected = _findModel(expectedModel);
    if (resolvedExpected != null) return resolvedExpected;

    return _findFallbackModel(effectiveModel, expectedModel);
  }

  Future<List<GeminiModel>> _listModels() async {
    final response = await _api.get('models');
    return GeminiModel.jsonToList(response.data['models']);
  }

  String? _findModel(String modelName) {
    final models = _models!;
    if (models.any((m) => m.name == modelName)) return modelName;

    final withPrefix = 'models/$modelName';
    if (models.any((m) => m.name == withPrefix)) return withPrefix;

    final partialMatches = models
        .where((m) =>
            m.name?.toLowerCase().contains(modelName.toLowerCase()) ?? false)
        .toList();

    if (partialMatches.isNotEmpty) {
      partialMatches.sort(_compareModelVersions);
      final bestMatch = partialMatches.first.name!;
      log('Using partial match "$bestMatch" for requested model "$modelName"',
          name: 'GEMINI_INFO');
      return bestMatch;
    }

    return null;
  }

  String _findFallbackModel(String? userModel, String expectedModel) {
    log('Expected model "$expectedModel" not found. Searching for alternatives...',
        name: 'GEMINI_WARNING');

    final fallback = _findBestFallback(userModel, expectedModel);
    if (fallback != null) {
      log('Using fallback model: $fallback', name: 'GEMINI_INFO');
      return fallback;
    }

    log('No suitable model found. Using default: ${Constants.defaultModel}',
        name: 'GEMINI_WARNING');
    return Constants.defaultModel;
  }

  void _logModelNotFound(String modelName) {
    log('Model "$modelName" not found. Available: ${_models?.map((e) => e.name).join(", ")}',
        name: 'GEMINI_WARNING');
  }

  int _compareModelVersions(GeminiModel a, GeminiModel b) {
    final versionA = _extractVersion(a.name ?? '');
    final versionB = _extractVersion(b.name ?? '');
    return versionB.compareTo(versionA);
  }

  double _extractVersion(String name) {
    final match = RegExp(r'(\d+\.?\d*)').firstMatch(name);
    return double.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  String? _findBestFallback(String? userModel, String expectedModel) {
    if (_models == null || _models!.isEmpty) return null;
    final fallbackPriority = ['gemini-2.5-pro', 'gemini-2.5-flash'];
    final userHint = userModel?.toLowerCase();
    final expectedHint = expectedModel.toLowerCase();

    if (userHint?.contains('pro') ?? expectedHint.contains('pro')) {
      return _findModelByPatterns(['pro', ...fallbackPriority]);
    }
    if (userHint?.contains('flash') ?? expectedHint.contains('flash')) {
      return _findModelByPatterns(['flash', ...fallbackPriority]);
    }
    return _findModelByPatterns(fallbackPriority);
  }

  String? _findModelByPatterns(List<String> patterns) {
    for (final pattern in patterns) {
      final matches = _models!
          .where((m) => m.name?.toLowerCase().contains(pattern) ?? false)
          .toList();
      if (matches.isNotEmpty) {
        matches.sort(_compareModelVersions);
        return matches.first.name;
      }
    }
    return null;
  }
}
