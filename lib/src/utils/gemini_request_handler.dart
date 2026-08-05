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

  bool get _isOpenAi {
    final baseUrl = _api.dio.options.baseUrl;
    if (baseUrl.contains('openai')) return true;
    // Also detect by model name — gpt-*, o1-*, o3-*, o4-* are OpenAI model families.
    final model = Gemini.instance.defaultModel ?? '';
    return model.startsWith('gpt-') ||
        model.startsWith('o1') ||
        model.startsWith('o3') ||
        model.startsWith('o4');
  }

  Map<String, Object> _transformForOpenAi({
    required String endpoint,
    Map<String, Object>? data,
    GenerationConfig? generationConfig,
    required bool isStream,
  }) {
    String modelName = endpoint.split(':').first;
    if (modelName.startsWith('models/')) {
      modelName = modelName.substring(7);
    }
    if (modelName.isEmpty || modelName == 'models') {
      modelName = Gemini.instance.defaultModel ?? 'gpt-4o-mini';
      if (modelName.startsWith('models/')) {
        modelName = modelName.substring(7);
      }
    }

    final openAiMessages = <Map<String, dynamic>>[];

    // Handle system_instruction (Gemini format) → system role message (OpenAI format).
    if (data != null && data.containsKey('system_instruction')) {
      final sysInstruction = data['system_instruction'];
      String sysText = '';
      if (sysInstruction is Map<String, dynamic>) {
        final parts = sysInstruction['parts'] as List?;
        if (parts != null) {
          for (final p in parts) {
            if (p is Map<String, dynamic> && p['text'] != null) {
              sysText += p['text'].toString();
            }
          }
        }
      }
      if (sysText.isNotEmpty) {
        openAiMessages.add({'role': 'system', 'content': sysText});
      }
    }

    if (data != null && data.containsKey('contents')) {
      final contents = data['contents'] as List?;
      if (contents != null) {
        for (final c in contents) {
          if (c is Map<String, dynamic>) {
            final geminiRole = c['role']?.toString();
            final role = (geminiRole == 'model') ? 'assistant' : (geminiRole ?? 'user');
            final parts = c['parts'] as List?;
            final textBuffer = StringBuffer();
            if (parts != null) {
              for (final p in parts) {
                if (p is Map<String, dynamic> && p['text'] != null) {
                  textBuffer.write(p['text']);
                }
              }
            }
            openAiMessages.add({
              'role': role,
              'content': textBuffer.toString(),
            });
          }
        }
      }
    } else if (data != null) {
      String text = '';
      if (data.containsKey('text')) {
        text = data['text'].toString();
      }
      if (text.isNotEmpty) {
        openAiMessages.add({'role': 'user', 'content': text});
      }
    }

    final lastMessageText = openAiMessages.lastOrNull?['content']?.toString() ?? '';

    final openAiPayload = <String, Object>{
      'model': modelName,
      'messages': openAiMessages,
      'input': lastMessageText,
    };

    if (isStream) {
      openAiPayload['stream'] = true;
    }

    if (generationConfig != null) {
      if (generationConfig.temperature != null) {
        openAiPayload['temperature'] = generationConfig.temperature!;
      }
      if (generationConfig.maxOutputTokens != null) {
        openAiPayload['max_output_tokens'] = generationConfig.maxOutputTokens!;
      }
      if (generationConfig.topP != null) {
        openAiPayload['top_p'] = generationConfig.topP!;
      }
      if (generationConfig.stopSequences != null && generationConfig.stopSequences!.isNotEmpty) {
        openAiPayload['stop'] = generationConfig.stopSequences!;
      }
      if (generationConfig.responseMimeType == 'application/json') {
        openAiPayload['response_format'] = {'type': 'json_object'};
      }
    }

    return openAiPayload;
  }

  String _resolveOpenAiEndpoint(String originalEndpoint, {bool isGetRequest = false}) {
    if (isGetRequest) return 'models';

    final baseUrl = _api.dio.options.baseUrl.toLowerCase();
    if (baseUrl.endsWith('/responses') || baseUrl.endsWith('/responses/')) {
      return '';
    }
    if (baseUrl.endsWith('/chat/completions') || baseUrl.endsWith('/chat/completions/')) {
      return '';
    }
    if (baseUrl.contains('openai')) {
      return 'chat/completions';
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
          _isOpenAi ? _resolveOpenAiEndpoint(endpoint, isGetRequest: isGetRequest) : endpoint;
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
          _isOpenAi ? _resolveOpenAiEndpoint(endpoint, isGetRequest: false) : endpoint;
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
