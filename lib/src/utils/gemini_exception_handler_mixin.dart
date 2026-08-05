import 'package:dio/dio.dart';
import 'package:flutter_gemini/src/repository/api_interface.dart';
import 'package:flutter_gemini/src/utils/gemini_exception.dart';

/// A mixin that provides centralized exception handling for API requests.
/// This is designed to simplify error management by wrapping requests
/// with a handler that detects and processes exceptions.
///
/// **Usage:**
/// Add this mixin to a class implementing `ApiInterface` to gain access
/// to the `handler` method for streamlined API call management.
///
/// **Example:**
/// ```dart
/// class ApiService with GeminiExceptionHandler implements ApiInterface {
///   Future<Response> fetchData() async {
///     return await handler(() async {
///       return await dio.get('/endpoint');
///     });
///   }
/// }
/// ```
mixin GeminiExceptionHandler on ApiInterface {
  /// Wraps an API request and handles potential exceptions.
  ///
  /// **Parameters:**
  /// - `request` (Future<Response> Function()): A function that executes
  ///   the actual API request and returns a `Future<Response>`.
  ///
  /// **Returns:**
  /// - `Future<Response>`: The API response if the request succeeds.
  ///
  /// **Throws:**
  /// - `GeminiException`: If the response indicates an error or if a
  ///   DioException occurs.
  Future<Response> handler(Future<Response> Function() request) async {
    try {
      // Execute the API request.
      final res = await request();

      // Extract the HTTP status code.
      int statusCode = res.statusCode ?? 200;

      // If the status code indicates success, return the response.
      if (statusCode >= 200 && statusCode < 300) {
        return res;
      }

      Object? errorMsg;
      dynamic details;

      if (res.data is Map) {
        final mapData = res.data as Map;
        final error = mapData['error'];
        if (error is Map) {
          errorMsg = error['message'] ?? error;
          details = error['details'];
        } else {
          errorMsg = error ?? res.data;
        }
      } else {
        errorMsg = res.data;
      }

      throw GeminiApiException(
        errorMsg ?? 'API error ($statusCode)',
        statusCode: statusCode,
        details: details,
      );
    } catch (e) {
      if (e is GeminiException) {
        rethrow;
      }

      // Handle Dio-specific exceptions.
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final data = e.response?.data;

        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          throw GeminiNetworkException(
            e.message ?? 'Network connection failed or timed out',
            statusCode: statusCode,
          );
        }

        if (data != null && data is Map) {
          final error = data['error'];
          final message = error is Map
              ? (error['message'] ?? e.message)
              : (error ?? e.message ?? 'API Error');
          final details = error is Map ? error['details'] : null;
          throw GeminiApiException(
            message,
            statusCode: statusCode ?? 500,
            details: details,
          );
        }

        if (statusCode != null) {
          throw GeminiApiException(
            e.message ?? 'HTTP Error $statusCode',
            statusCode: statusCode,
          );
        }

        throw GeminiNetworkException(
          e.message ?? 'Network error occurred',
          statusCode: statusCode,
        );
      }

      // For all other exceptions, wrap in GeminiApiException or GeminiException.
      throw GeminiApiException(e.toString(), statusCode: -1);
    }
  }
}
