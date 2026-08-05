# Task: Enhance `flutter_gemini` Package with Custom Base URL, Global/Custom Models, Max Tokens, and Dynamic Config Support

## Context & Overview

The `flutter_gemini` package currently hardcodes certain assumptions about model names, API version pathing, and default generation parameters. When integrating Gemini into applications with server-driven configuration (e.g., Remote Config, custom proxy gateways, or dynamic backend routing), developers need full flexibility to customize:

1. **Custom Base URL & Path Formatting**: Support custom proxy endpoints, API gateways, and custom backend proxies without forcing Google's `/v1beta/` path structure.
2. **Global Default Model & Per-Request Overrides**: Configure a global default model in `Gemini.init()` (e.g. `gemini-2.5-flash`, `gemini-1.5-pro`) and allow dynamic per-request overrides.
3. **Global & Per-Request Max Tokens / GenerationConfig Merging**: Configure default `GenerationConfig` (e.g., `maxOutputTokens`, `temperature`, `topK`, `topP`) globally at initialization and merge it safely with per-request overrides.
4. **Custom Headers & Authentication Options**: Support passing custom authorization headers (e.g. `Authorization: Bearer ...` or custom API key headers for proxy servers).
5. **Robust Error Handling & Timeout Management**: Provide typed exceptions for network, API rate limits, and config errors.

---

## Phase 1 — Update `Gemini` Core Initialization (`lib/src/init.dart`)

### 1.1 Extend `Gemini.init()` and `Gemini.reInitialize()`

Add the following optional parameters to `Gemini.init()` and `Gemini.reInitialize()`:
- `String? defaultModel`: Sets the global fallback model name (defaults to `Constants.defaultModel` if null).
- `bool includeVersionInBaseUrl`: Controls whether `${version}/` is automatically appended to `baseURL` (default `true`). If set to `false`, `baseURL` is used as an absolute URI endpoint.
- `Map<String, dynamic>? customHeaders`: Custom headers for proxy/gateway requests.

```dart
factory Gemini.init({
  required String apiKey,
  String? baseURL,
  String? defaultModel,
  GenerationConfig? generationConfig,
  List<SafetySetting>? safetySettings,
  Map<String, dynamic>? headers,
  bool? enableDebugging,
  String? version,
  bool includeVersionInBaseUrl = true,
  bool disableAutoUpdateModelName = false,
});
```

### 1.2 Update Instance Properties

Store `defaultModel`, `includeVersionInBaseUrl`, and global `generationConfig` on the `Gemini` instance:
```dart
class Gemini {
  String apiKey;
  String? defaultModel;
  GenerationConfig? defaultGenerationConfig;
  bool includeVersionInBaseUrl;
  // ...
}
```

---

## Phase 2 — Dio & Service Layer Enhancements (`lib/src/implement/gemini_service.dart`)

### 2.1 Base URL & Path Resolver

Update `GeminiService` constructor to resolve the base URL cleanly without forcing path concatenation when `includeVersionInBaseUrl` is `false`:

```dart
final String resolvedBaseUrl = includeVersionInBaseUrl
    ? '${baseURL ?? Constants.baseUrl}${version ?? Constants.defaultVersion}/'
    : (baseURL ?? Constants.baseUrl);

final Dio dio = Dio(
  BaseOptions(
    baseUrl: resolvedBaseUrl,
    contentType: 'application/json',
    headers: headers,
  ),
);
```

### 2.2 Flexible Header & Query Injector

Support custom authentication mechanisms:
- If `apiKey` is provided and query parameter `key` is used, retain standard behavior.
- Support custom authorization headers (e.g., `x-api-key` or `Authorization: Bearer <token>`) when specified in `headers`.

---

## Phase 3 — GenerationConfig & Model Merging (`lib/src/implement/gemini_implement.dart`)

### 3.1 Model Resolution Logic

In `GeminiImpl`, resolve model names dynamically:
```dart
String resolveModelName(String? perRequestModel) {
  if (perRequestModel != null && perRequestModel.trim().isNotEmpty) {
    return perRequestModel.trim();
  }
  if (defaultModel != null && defaultModel!.trim().isNotEmpty) {
    return defaultModel!.trim();
  }
  return Constants.defaultModel;
}
```

### 3.2 GenerationConfig Merging Logic

When a method receives a per-request `GenerationConfig`, merge non-null fields with the global `defaultGenerationConfig`:

```dart
GenerationConfig mergeGenerationConfig({
  GenerationConfig? globalConfig,
  GenerationConfig? requestConfig,
}) {
  if (globalConfig == null) return requestConfig ?? GenerationConfig();
  if (requestConfig == null) return globalConfig;

  return GenerationConfig(
    stopSequences: requestConfig.stopSequences ?? globalConfig.stopSequences,
    temperature: requestConfig.temperature ?? globalConfig.temperature,
    maxOutputTokens: requestConfig.maxOutputTokens ?? globalConfig.maxOutputTokens,
    topP: requestConfig.topP ?? globalConfig.topP,
    topK: requestConfig.topK ?? globalConfig.topK,
    responseMimeType: requestConfig.responseMimeType ?? globalConfig.responseMimeType,
  );
}
```

---

## Phase 4 — Update All Public API Methods (`lib/src/implement/gemini_implement.dart`)

Update public API calls (`prompt`, `promptStream`, `chat`, `streamChat`, `text`, `textAndImage`, `countTokens`, `embedding`) to:
1. Automatically resolve model name via `resolveModelName(modelName)`.
2. Automatically merge generation config via `mergeGenerationConfig(globalConfig, requestConfig)`.
3. Support optional `CancelToken` and `TimeoutConfig`.

---

## Phase 5 — Typed Exceptions & Error Handling (`lib/src/models/gemini_exception.dart`)

Create `GeminiException` hierarchy:
- `GeminiApiException`: returned when Gemini backend responds with error status (e.g., 400, 403, 429, 500). Contains `statusCode`, `message`, `details`.
- `GeminiNetworkException`: returned when connection fails or times out.
- `GeminiConfigException`: returned when invalid base URL, missing API key, or invalid parameter range is passed.

---

## Phase 6 — Verification & Testing Checklist

- [ ] **Unit Test**: `Gemini.init` with custom `baseURL` (with `includeVersionInBaseUrl: false`).
- [ ] **Unit Test**: `Gemini.init` with `defaultModel` and verify requests use `defaultModel` when per-request model is omitted.
- [ ] **Unit Test**: `GenerationConfig` merging (verify global `maxOutputTokens` applies if not overridden per-request).
- [ ] **Unit Test**: Per-request `model` and `maxOutputTokens` override global defaults correctly.
- [ ] **Unit Test**: Exception handling for HTTP 400, 429 (Rate Limit), and timeouts.
