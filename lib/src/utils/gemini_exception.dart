/// A custom exception class to represent errors that occur during Gemini API interactions.
/// This exception is used to capture error messages and status codes from the API response,
/// providing more context for error handling.
///
/// **Usage:**
/// You can throw a `GeminiException` when an API request fails or encounters an unexpected issue.
///
/// **Example:**
/// ```dart
/// if (response.statusCode != 200) {
///   throw GeminiException('Failed to fetch data', statusCode: response.statusCode);
/// }
/// ```
/// Base exception class for Gemini SDK errors.
class GeminiException implements Exception {
  final Object message;
  final int? statusCode;

  const GeminiException(
    this.message, {
    this.statusCode,
  });

  @override
  String toString() {
    return '**GeminiException** => $message\n\tStatus Code: $statusCode';
  }
}

/// Thrown when the Gemini API server returns an error (HTTP status 400, 403, 429, 500, etc.).
class GeminiApiException extends GeminiException {
  final dynamic details;

  const GeminiApiException(
    super.message, {
    super.statusCode,
    this.details,
  });

  @override
  String toString() {
    return '**GeminiApiException** [$statusCode] => $message${details != null ? '\n\tDetails: $details' : ''}';
  }
}

/// Thrown when a network error, connection failure, or request timeout occurs.
class GeminiNetworkException extends GeminiException {
  const GeminiNetworkException(
    super.message, {
    super.statusCode,
  });

  @override
  String toString() {
    return '**GeminiNetworkException** => $message${statusCode != null ? '\n\tStatus Code: $statusCode' : ''}';
  }
}

/// Thrown when invalid configuration is provided (e.g. invalid base URL, missing API key, invalid parameter).
class GeminiConfigException extends GeminiException {
  const GeminiConfigException(
    super.message, {
    super.statusCode,
  });

  @override
  String toString() {
    return '**GeminiConfigException** => $message';
  }
}
