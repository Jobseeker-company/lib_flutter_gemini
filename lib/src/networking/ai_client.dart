import 'dart:convert';

import 'package:dio/dio.dart';

import 'ai_exception.dart';
import 'sse_transformer.dart';

/// Authentication mode for the AI provider.
enum AiAuthMode {
  /// Google Gemini style: API key as query param `key` + header `x-goog-api-key`.
  gemini,

  /// OpenAI / Bearer token style: `Authorization: Bearer <key>`.
  bearer,

  /// Custom: caller provides headers manually via [AiClient.custom].
  custom,
}

/// Configuration for an [AiClient].
class AiClientConfig {
  /// Base URL for all requests (e.g. `https://generativelanguage.googleapis.com/v1/`).
  final String baseUrl;

  /// API key used for authentication.
  final String apiKey;

  /// How to attach the API key to requests.
  final AiAuthMode authMode;

  /// Additional headers merged into every request.
  final Map<String, String> headers;

  /// Request timeout. Defaults to 30 seconds if null.
  final Duration timeout;

  /// Whether to enable debug logging.
  final bool enableDebugging;

  const AiClientConfig({
    required this.baseUrl,
    required this.apiKey,
    this.authMode = AiAuthMode.gemini,
    this.headers = const {},
    this.timeout = const Duration(seconds: 30),
    this.enableDebugging = false,
  });
}

/// Provider-agnostic AI HTTP client.
///
/// Inspired by OpenAI's [OpenAINetworkingClient] but generalised to work
/// with Gemini, OpenAI, Anthropic, or any OpenAI-compatible proxy.
///
/// Provides:
/// - `get<T>` — typed GET request
/// - `post<T>` — typed POST request
/// - `postStream<T>` — typed SSE streaming POST request
/// - `cancelRequest` — cancel in-flight requests
class AiClient {
  final Dio _dio;
  final AiClientConfig config;
  CancelToken? _cancelToken;

  AiClient._(this._dio, this.config);

  /// Creates an [AiClient] for Google Gemini API.
  ///
  /// Uses query-param + header auth (`key=...` + `x-goog-api-key`).
  factory AiClient.gemini({
    required String apiKey,
    String baseUrl = 'https://generativelanguage.googleapis.com/v1/',
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
    bool enableDebugging = false,
  }) {
    final config = AiClientConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      authMode: AiAuthMode.gemini,
      headers: headers,
      timeout: timeout,
      enableDebugging: enableDebugging,
    );
    final dio = Dio(BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.timeout,
      receiveTimeout: config.timeout,
      sendTimeout: config.timeout,
      headers: {'Content-Type': 'application/json', ...config.headers},
    ));
    if (enableDebugging) {
      dio.interceptors
          .add(LogInterceptor(requestBody: true, responseBody: true));
    }
    return AiClient._(dio, config);
  }

  /// Creates an [AiClient] for OpenAI or any OpenAI-compatible endpoint.
  ///
  /// Uses `Authorization: Bearer <apiKey>` header.
  factory AiClient.openai({
    required String apiKey,
    String baseUrl = 'https://api.openai.com/v1/',
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
    bool enableDebugging = false,
  }) {
    final config = AiClientConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      authMode: AiAuthMode.bearer,
      headers: headers,
      timeout: timeout,
      enableDebugging: enableDebugging,
    );
    final dio = Dio(BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.timeout,
      receiveTimeout: config.timeout,
      sendTimeout: config.timeout,
      headers: {'Content-Type': 'application/json', ...config.headers},
    ));
    if (enableDebugging) {
      dio.interceptors
          .add(LogInterceptor(requestBody: true, responseBody: true));
    }
    return AiClient._(dio, config);
  }

  /// Creates an [AiClient] with a pre-built [Dio] instance and custom config.
  ///
  /// Use this when you need full control over Dio configuration,
  /// interceptors, or authentication.
  factory AiClient.custom({
    required Dio dio,
    required AiClientConfig config,
  }) {
    if (config.enableDebugging) {
      dio.interceptors
          .add(LogInterceptor(requestBody: true, responseBody: true));
    }
    return AiClient._(dio, config);
  }

  // ─── Auth helpers ───────────────────────────────────────────────────

  Map<String, dynamic> _queryParams() {
    if (config.authMode == AiAuthMode.gemini &&
        config.apiKey.trim().isNotEmpty) {
      return {'key': config.apiKey.trim()};
    }
    return {};
  }

  Map<String, dynamic> _requestHeaders() {
    final h = <String, dynamic>{};
    if (config.apiKey.trim().isNotEmpty) {
      switch (config.authMode) {
        case AiAuthMode.gemini:
          h['x-goog-api-key'] = config.apiKey.trim();
          break;
        case AiAuthMode.bearer:
          h['Authorization'] = 'Bearer ${config.apiKey.trim()}';
          break;
        case AiAuthMode.custom:
          // Caller is responsible for headers via config.headers or Dio interceptors
          break;
      }
    }
    return h;
  }

  Options _options({ResponseType? responseType, Duration? timeout}) {
    return Options(
      headers: _requestHeaders(),
      responseType: responseType,
      receiveTimeout: timeout ?? config.timeout,
      sendTimeout: timeout ?? config.timeout,
    );
  }

  // ─── GET ─────────────────────────────────────────────────────────────

  /// Sends a GET request and decodes the JSON response into type [T].
  ///
  /// [from] is the endpoint path (appended to [config.baseUrl]).
  /// [onSuccess] converts the decoded JSON map into type [T].
  Future<T> get<T>({
    required String from,
    required T Function(Map<String, dynamic>) onSuccess,
    Duration? timeout,
  }) async {
    _cancelToken ??= CancelToken();
    try {
      final response = await _dio.get(
        from,
        queryParameters: _queryParams(),
        options: _options(timeout: timeout),
        cancelToken: _cancelToken,
      );
      return onSuccess(_decodeResponse(response));
    } on DioException catch (e) {
      throw _mapDioException(e);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiApiException(e.toString(), statusCode: -1);
    }
  }

  /// Sends a raw GET request and returns the Dio [Response] directly.
  ///
  /// Useful when you need access to status codes, raw headers, etc.
  Future<Response> getRaw({
    required String from,
    Duration? timeout,
  }) async {
    _cancelToken ??= CancelToken();
    try {
      return await _dio.get(
        from,
        queryParameters: _queryParams(),
        options: _options(timeout: timeout),
        cancelToken: _cancelToken,
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  // ─── POST ────────────────────────────────────────────────────────────

  /// Sends a POST request and decodes the JSON response into type [T].
  ///
  /// [to] is the endpoint path.
  /// [body] is the request payload (will be JSON-encoded).
  /// [onSuccess] converts the decoded JSON map into type [T].
  Future<T> post<T>({
    required String to,
    Map<String, dynamic>? body,
    required T Function(Map<String, dynamic>) onSuccess,
    Duration? timeout,
  }) async {
    _cancelToken ??= CancelToken();
    try {
      final response = await _dio.post(
        to,
        data: body != null ? jsonEncode(body) : null,
        queryParameters: _queryParams(),
        options: _options(timeout: timeout),
        cancelToken: _cancelToken,
      );
      return onSuccess(_decodeResponse(response));
    } on DioException catch (e) {
      throw _mapDioException(e);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiApiException(e.toString(), statusCode: -1);
    }
  }

  /// Sends a raw POST request and returns the Dio [Response] directly.
  ///
  /// Used internally by the Gemini service layer which needs the raw
  /// response for its own parsing.
  Future<Response> postRaw({
    required String to,
    Map<String, dynamic>? body,
    bool isStreamResponse = false,
    Duration? timeout,
  }) async {
    _cancelToken ??= CancelToken();
    try {
      final response = await _dio.post(
        to,
        data: body != null ? jsonEncode(body) : null,
        queryParameters: _queryParams(),
        options: _options(
          timeout: timeout,
          responseType: isStreamResponse ? ResponseType.stream : null,
        ),
        cancelToken: _cancelToken,
      );
      return response;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  // ─── STREAMING POST ──────────────────────────────────────────────────

  /// Sends a POST request with `stream: true` and yields parsed SSE events.
  ///
  /// Each SSE data line is decoded from JSON and passed through [onSuccess]
  /// to produce typed items for the stream.
  ///
  /// Works with both Gemini-style raw JSON streaming and OpenAI-style
  /// `data: {...}` SSE streaming.
  Stream<T> postStream<T>({
    required String to,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) onSuccess,
    Duration? timeout,
  }) async* {
    _cancelToken ??= CancelToken();
    Response<ResponseBody> response;
    try {
      response = await _dio.post(
        to,
        data: jsonEncode(body),
        queryParameters: _queryParams(),
        options: Options(
          headers: _requestHeaders(),
          responseType: ResponseType.stream,
          receiveTimeout: timeout ?? config.timeout,
          sendTimeout: timeout ?? config.timeout,
        ),
        cancelToken: _cancelToken,
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }

    if (response.statusCode != 200) {
      throw AiApiException(
        'Stream request failed with status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final responseBody = response.data;
    if (responseBody == null) return;

    yield* parseSseStream(responseBody.stream).map(onSuccess);
  }

  // ─── CANCEL ─────────────────────────────────────────────────────────

  /// Cancels the current in-flight request, if any.
  Future<void> cancelRequest() async {
    if (_cancelToken != null) {
      _cancelToken!.cancel();
      _cancelToken = null;
    }
  }

  // ─── INTERNAL ────────────────────────────────────────────────────────

  Map<String, dynamic> _decodeResponse(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    throw AiApiException(
      'Unexpected response format: ${data.runtimeType}',
      statusCode: response.statusCode,
    );
  }

  /// Maps a [DioException] to the appropriate [AiException] subclass.
  AiException _mapDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return AiNetworkException(
        e.message ?? 'Network connection failed or timed out',
        statusCode: statusCode,
      );
    }

    if (data is Map) {
      final error = data['error'];
      final message = error is Map
          ? (error['message'] ?? e.message)
          : (error ?? e.message ?? 'API Error');
      final details = error is Map ? error['details'] : null;
      return AiApiException(
        message.toString(),
        statusCode: statusCode ?? 500,
        details: details,
      );
    }

    if (statusCode != null) {
      return AiApiException(
        e.message ?? 'HTTP Error $statusCode',
        statusCode: statusCode,
      );
    }

    return AiNetworkException(
      e.message ?? 'Network error occurred',
      statusCode: statusCode,
    );
  }
}
