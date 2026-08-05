import 'package:dio/dio.dart';
import 'package:flutter_gemini/src/models/timeout_config/timeout_config.dart';
import 'package:flutter_gemini/src/models/generation_config/generation_config.dart';
import 'package:flutter_gemini/src/models/gemini_safety/gemini_safety.dart';
import 'package:flutter_gemini/src/utils/gemini_response_parser.dart';
import 'package:flutter_gemini/src/implement/gemini_service.dart';
import 'package:flutter_gemini/src/init.dart';
import 'package:flutter_gemini/src/models/candidates/candidates.dart';

class GeminiRequestHandler {
  final GeminiService _api;

  GeminiRequestHandler(this._api);

  bool get _isOpenAi =>
      _api.dio.options.baseUrl.contains('openai.com') ||
      _api.dio.options.baseUrl.contains('openai');

  Map<String, Object> _transformForOpenAi({
    required String endpoint,
    Map<String, Object>? data,
    GenerationConfig? generationConfig,
    required bool isStream,
  }) {
    String modelName = endpoint.split(':').first;
    if (modelName.isEmpty || modelName == 'models') {
      modelName = 'gpt-4.1';
    }

    String promptText = '';
    if (data != null && data.containsKey('contents')) {
      final contents = data['contents'] as List?;
      if (contents != null && contents.isNotEmpty) {
        final lastContent = contents.last as Map<String, dynamic>?;
        final parts = lastContent?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final firstPart = parts.first as Map<String, dynamic>?;
          promptText = firstPart?['text']?.toString() ?? '';
        }
      }
    }

    final openAiPayload = <String, Object>{
      'model': modelName,
      'input': promptText,
    };

    if (isStream) {
      openAiPayload['stream'] = true;
    }
    if (generationConfig?.temperature != null) {
      openAiPayload['temperature'] = generationConfig!.temperature!;
    }
    if (generationConfig?.maxOutputTokens != null) {
      openAiPayload['max_output_tokens'] = generationConfig!.maxOutputTokens!;
    }

    return openAiPayload;
  }

  String _resolveOpenAiEndpoint(String originalEndpoint) {
    if (_api.dio.options.baseUrl.endsWith('/responses') ||
        _api.dio.options.baseUrl.endsWith('/responses/')) {
      return '';
    }
    return 'responses';
  }

  /// Executes a standard API request.
  Future<T> executeRequest<T>({
    required String endpoint,
    Map<String, Object>? data,
    required T Function(Map<String, dynamic>) responseParser,
    bool isGetRequest = false,
    GenerationConfig? generationConfig,
    List<SafetySetting>? safetySettings,
    TimeoutConfig? timeoutConfig,
  }) async {
    _clearTypeProvider();
    try {
      final targetEndpoint =
          _isOpenAi && !isGetRequest ? _resolveOpenAiEndpoint(endpoint) : endpoint;
      final payloadData = _isOpenAi && !isGetRequest
          ? _transformForOpenAi(
              endpoint: endpoint,
              data: data,
              generationConfig: generationConfig,
              isStream: false,
            )
          : data;

      final Response response = isGetRequest
          ? await _api.get(targetEndpoint, timeout: timeoutConfig)
          : await _api.post(
              targetEndpoint,
              data: payloadData,
              generationConfig: _isOpenAi ? null : generationConfig,
              safetySettings: _isOpenAi ? null : safetySettings,
              timeout: timeoutConfig,
            );
      return responseParser(response.data);
    } finally {
      _setTypeProviderLoading(false);
    }
  }

  /// Executes a streaming API request.
  Stream<Candidates> executeStreamRequest({
    required String endpoint,
    required Map<String, Object> data,
    GenerationConfig? generationConfig,
    List<SafetySetting>? safetySettings,
    TimeoutConfig? timeoutConfig,
  }) async* {
    _clearTypeProvider();
    try {
      final targetEndpoint =
          _isOpenAi ? _resolveOpenAiEndpoint(endpoint) : endpoint;
      final payloadData = _isOpenAi
          ? _transformForOpenAi(
              endpoint: endpoint,
              data: data,
              generationConfig: generationConfig,
              isStream: true,
            )
          : data;

      final response = await _api.post(
        targetEndpoint,
        data: payloadData,
        generationConfig: _isOpenAi ? null : generationConfig,
        safetySettings: _isOpenAi ? null : safetySettings,
        isStreamResponse: true,
        timeout: timeoutConfig,
      );

      if (response.statusCode == 200) {
        yield* GeminiResponseParser.processStreamResponse(response.data);
      }
    } finally {
      _setTypeProviderLoading(false);
    }
  }

  void _clearTypeProvider() => Gemini.instance.typeProvider?.clear();
  void _setTypeProviderLoading(bool loading) =>
      Gemini.instance.typeProvider?.loading = loading;
}
