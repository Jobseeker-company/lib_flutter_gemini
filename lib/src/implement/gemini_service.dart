import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter_gemini/src/models/timeout_config/timeout_config.dart';
import 'package:flutter_gemini/src/repository/api_interface.dart';
import 'package:flutter_gemini/src/utils/gemini_exception_handler_mixin.dart';
import '../init.dart';
import '../models/gemini_safety/gemini_safety.dart';
import '../models/generation_config/generation_config.dart';

/// [GeminiService] is an API helper service class that extends [ApiInterface] and mixes in [GeminiExceptionHandler].
/// This service is used for making HTTP requests (POST, GET) to interact with the Gemini API.
class GeminiService extends ApiInterface with GeminiExceptionHandler {
  final Dio dio; // Dio instance for making HTTP requests.
  final String apiKey; // The API key for authenticating requests.
  CancelToken? cancelToken; // Token used to cancel HTTP requests.

  /// Returns true when the configured base URL points to an OpenAI-compatible endpoint.
  /// This covers api.openai.com as well as custom proxy servers that include 'openai'
  /// anywhere in the URL (e.g. my-openai-proxy.example.com).
  bool get _isOpenAiUrl => dio.options.baseUrl.contains('openai');

  /// Constructor for [GeminiService]. Optionally enables logging for debugging.
  GeminiService(this.dio, {required this.apiKey}) {
    if ((Gemini.enableDebugging ?? false)) {
      dio.interceptors.add(LogInterceptor(
          requestBody: true,
          responseBody: true)); // Adds logging if debugging is enabled.
    }
  }

  /// Sends a POST request to the Gemini API.
  ///
  /// [route] is the endpoint route.
  /// [data] contains the body of the request.
  /// [generationConfig] configures generation parameters for the request.
  /// [safetySettings] configures safety settings for the request.
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
    cancelToken ??= CancelToken(); // Ensure cancelToken is initialized.

    // Only inject Gemini-specific wrappers when NOT using an OpenAI-compatible endpoint.
    // When _isOpenAiUrl is true, the request payload is already fully formed by
    // GeminiRequestHandler._transformForOpenAi(), so we must not override it here.
    if (!_isOpenAiUrl) {
      // If safetySettings are provided, include them in the request data.
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

      // If generationConfig is provided, include it in the request data.
      if (generationConfig != null || this.generationConfig != null) {
        data?['generationConfig'] =
            generationConfig?.toJson() ?? this.generationConfig?.toJson() ?? {};
      }
    }

    if (timeout != null) {
      log(timeout.debug());
    }

    Map<String, dynamic>? queryParams;
    Map<String, dynamic>? requestHeaders;

    if (apiKey.trim().isNotEmpty) {
      if (_isOpenAiUrl) {
        // OpenAI and OpenAI-compatible proxies use Bearer token auth.
        requestHeaders = {'Authorization': 'Bearer ${apiKey.trim()}'};
      } else {
        // Google Gemini uses both a query param and a header for auth.
        queryParams = {'key': apiKey.trim()};
        requestHeaders = {'x-goog-api-key': apiKey.trim()};
      }
    }

    // Make the POST request using Dio.
    return handler(() => dio.post(
          route,
          data: jsonEncode(data), // Encode the data as JSON.
          queryParameters: queryParams,
          options: Options(
            headers: requestHeaders,
            responseType: isStreamResponse == true ? ResponseType.stream : null,
            receiveTimeout: timeout?.receiveTimeout,
            sendTimeout: timeout?.sendTimeout,
          ), // Set response type if streaming is enabled.
          cancelToken: cancelToken, // Attach the cancel token.
        ));
  }

  /// Sends a GET request to the Gemini API.
  ///
  /// [route] is the endpoint route.
  @override
  Future<Response> get(String route, {TimeoutConfig? timeout}) async {
    cancelToken ??= CancelToken(); // Ensure cancelToken is initialized.

    if (timeout != null) {
      log(timeout.debug());
    }
    Map<String, dynamic>? queryParams;
    Map<String, dynamic>? requestHeaders;

    if (apiKey.trim().isNotEmpty) {
      if (_isOpenAiUrl) {
        // OpenAI and OpenAI-compatible proxies use Bearer token auth.
        requestHeaders = {'Authorization': 'Bearer ${apiKey.trim()}'};
      } else {
        // Google Gemini uses both a query param and a header for auth.
        queryParams = {'key': apiKey.trim()};
        requestHeaders = {'x-goog-api-key': apiKey.trim()};
      }
    }
    // Make the GET request using Dio.
    return handler(() => dio.get(route,
        queryParameters: queryParams,
        options: Options(
          headers: requestHeaders,
          receiveTimeout: timeout?.receiveTimeout,
          sendTimeout: timeout?.sendTimeout,
        ),
        cancelToken: cancelToken)); // Attach the cancel token.
  }

  /// Cancels an ongoing request if it exists.
  Future<void> cancelRequest() async {
    if (cancelToken != null) {
      cancelToken!.cancel(); // Cancel the request.
      cancelToken = null; // Nullify the cancel token.
    }
  }
}
