/// Provider-agnostic exception hierarchy for AI API interactions.
///
/// Mirrors the structure of [GeminiException] but decoupled from any
/// specific provider so the networking layer stays clean.
library;

/// Base exception for all AI SDK errors.
class AiException implements Exception {
  final Object message;
  final int? statusCode;

  const AiException(this.message, {this.statusCode});

  @override
  String toString() => '**AiException** => $message'
      '${statusCode != null ? '\n\tStatus Code: $statusCode' : ''}';
}

/// Thrown when the AI API server returns an error
/// (HTTP 400, 403, 429, 500, etc.).
class AiApiException extends AiException {
  final dynamic details;

  const AiApiException(super.message, {super.statusCode, this.details});

  @override
  String toString() => '**AiApiException** [$statusCode] => $message'
      '${details != null ? '\n\tDetails: $details' : ''}';
}

/// Thrown when a network error, connection failure, or request timeout occurs.
class AiNetworkException extends AiException {
  const AiNetworkException(super.message, {super.statusCode});

  @override
  String toString() => '**AiNetworkException** => $message'
      '${statusCode != null ? '\n\tStatus Code: $statusCode' : ''}';
}

/// Thrown when invalid configuration is provided
/// (e.g. invalid base URL, missing API key).
class AiConfigException extends AiException {
  const AiConfigException(super.message, {super.statusCode});

  @override
  String toString() => '**AiConfigException** => $message';
}
