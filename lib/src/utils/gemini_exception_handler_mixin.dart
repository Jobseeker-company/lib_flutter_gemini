import 'package:dio/dio.dart';
import 'package:flutter_gemini/src/repository/api_interface.dart';
import 'package:flutter_gemini/src/utils/gemini_exception.dart';
import 'package:flutter_gemini/src/networking/ai_exception.dart';

/// A mixin that provides centralized exception handling for API requests.
///
/// Supports both raw Dio errors (from direct Dio calls) and [AiException]
/// errors (from [AiClient] calls).
mixin GeminiExceptionHandler on ApiInterface {
  /// Wraps an API request and handles potential exceptions.
  ///
  /// Catches Dio errors, [AiException] from [AiClient], and generic errors,
  /// mapping them all to the [GeminiException] hierarchy.
  Future<Response> handler(Future<Response> Function() request) async {
    try {
      final res = await request();

      int statusCode = res.statusCode ?? 200;

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

      // Handle AiException thrown by AiClient — map to Gemini equivalents.
      if (e is AiApiException) {
        throw GeminiApiException(
          e.message,
          statusCode: e.statusCode,
          details: e.details,
        );
      }
      if (e is AiNetworkException) {
        throw GeminiNetworkException(
          e.message,
          statusCode: e.statusCode,
        );
      }
      if (e is AiConfigException) {
        throw GeminiConfigException(e.message);
      }

      // Handle Dio-specific exceptions (when AiClient is not used).
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

      // For all other exceptions, wrap in GeminiApiException.
      throw GeminiApiException(e.toString(), statusCode: -1);
    }
  }
}
