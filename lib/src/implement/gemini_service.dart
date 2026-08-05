import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter_gemini/src/models/timeout_config/timeout_config.dart';
import 'package:flutter_gemini/src/repository/api_interface.dart';
import 'package:flutter_gemini/src/utils/gemini_exception_handler_mixin.dart';
import 'package:flutter_gemini/src/networking/ai_client.dart';
import '../init.dart';
import '../models/gemini_safety/gemini_safety.dart';
import '../models/generation_config/generation_config.dart';

/// [GeminiService] is an API helper service class that extends [ApiInterface]
/// and mixes in [GeminiExceptionHandler].
///
/// Internally delegates HTTP calls to an [AiClient] instance, which handles
/// auth headers, timeouts, and error mapping for any provider (Gemini,
/// OpenAI, or OpenAI-compatible proxy).
class GeminiService extends ApiInterface with GeminiExceptionHandler {
  /// The underlying AiClient that handles auth, error mapping, and streaming.
  late final AiClient _aiClient;

  /// The underlying Dio instance, exposed for callers that need direct access
  /// (e.g. [GeminiRequestHandler] and [GeminiModelManager]).
  final Dio dio;

  /// The API key for authenticating requests.
  final String apiKey;

  CancelToken? cancelToken;

  /// Returns true when the configured base URL points to an OpenAI-compatible endpoint.
  bool get _isOpenAi => _aiClient.config.authMode == AiAuthMode.bearer;

  /// Creates a [GeminiService] with a Dio instance and API key.
  ///
  /// Automatically detects whether the base URL is for OpenAI (Bearer auth)
  /// or Gemini (query-param + header auth) and configures the internal
  /// [AiClient] accordingly.
  GeminiService(this.dio, {required this.apiKey}) {
    if ((Gemini.enableDebugging ?? false)) {
      dio.interceptors
          .add(LogInterceptor(requestBody: true, responseBody: true));
    }
    _aiClient = _buildAiClient(dio);
  }

  /// Builds an [AiClient] from the existing Dio instance.
  ///
  /// Detects whether to use Bearer auth (OpenAI) or Gemini auth based
  /// on the base URL.
  AiClient _buildAiClient(Dio dio) {
    final baseUrl = dio.options.baseUrl;
    final isOpenAi = baseUrl.contains('openai');

    // enableDebugging=false because GeminiService already adds LogInterceptor above.
    return AiClient.custom(
      dio: dio,
      config: AiClientConfig(
        baseUrl: baseUrl,
        apiKey: apiKey,
        authMode: isOpenAi ? AiAuthMode.bearer : AiAuthMode.gemini,
        enableDebugging: false,
      ),
    );
  }

  /// Sends a POST request to the API.
  ///
  /// [route] is the endpoint route.
  /// [data] contains the body of the request.
  /// [generationConfig] configures generation parameters.
  /// [safetySettings] configures safety settings.
  /// [isStreamResponse] determines whether the response should be streamed.
  @override
  Future<Response> post(
    String route, {
    required Map<String, Object>? data,
    GenerationConfig? generationConfig,
    List<SafetySetting>? safetySettings,
    bool isStreamResponse = false,
    TimeoutConfig? timeout,
  }) async {
    cancelToken ??= CancelToken();

    // Only inject Gemini-specific wrappers when NOT using an OpenAI-compatible endpoint.
    if (!_isOpenAi) {
      if (safetySettings != null || this.safetySettings != null) {
        final listSafetySettings = safetySettings ?? this.safetySettings ?? [];
        final items = [];
        for (final safetySetting in listSafetySettings) {
          items.add({
            'category': safetySetting.category.value,
            'threshold': safetySetting.threshold.value,
          });
        }
        data?['safetySettings'] = items;
      }

      if (generationConfig != null || this.generationConfig != null) {
        data?['generationConfig'] =
            generationConfig?.toJson() ?? this.generationConfig?.toJson() ?? {};
      }
    }

    if (timeout != null) {
      log(timeout.debug());
    }

    // Delegate to AiClient.postRaw — handles auth, error mapping, etc.
    return handler(() async {
      return await _aiClient.postRaw(
        to: route,
        body: data != null ? Map<String, dynamic>.from(data) : null,
        isStreamResponse: isStreamResponse,
        timeout: timeout?.receiveTimeout,
      );
    });
  }

  /// Sends a GET request to the API.
  ///
  /// [route] is the endpoint route.
  @override
  Future<Response> get(String route, {TimeoutConfig? timeout}) async {
    cancelToken ??= CancelToken();

    if (timeout != null) {
      log(timeout.debug());
    }

    // Delegate to AiClient.getRaw — handles auth, error mapping, etc.
    return handler(() async {
      return await _aiClient.getRaw(
        from: route,
        timeout: timeout?.receiveTimeout,
      );
    });
  }

  /// Sends a streaming POST request via the [AiClient].
  ///
  /// Returns an SSE-parsed stream of [Map<String, dynamic>] chunks.
  /// Used by [GeminiRequestHandler] for streaming responses.
  Stream<Map<String, dynamic>> postStream(
    String to,
    Map<String, dynamic> body,
  ) {
    return _aiClient.postStream<Map<String, dynamic>>(
      to: to,
      body: body,
      onSuccess: (data) => data,
    );
  }

  /// Cancels an ongoing request if it exists.
  Future<void> cancelRequest() async {
    await _aiClient.cancelRequest();
    if (cancelToken != null) {
      cancelToken = null;
    }
  }
}
