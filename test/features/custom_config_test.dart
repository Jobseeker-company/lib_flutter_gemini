import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:test/test.dart';

void main() {
  group('Gemini Custom Base URL and Properties', () {
    test(
        'Initialization with custom baseURL and includeVersionInBaseUrl: false',
        () {
      final gemini = Gemini.reInitialize(
        apiKey: 'test-api-key',
        baseURL: 'https://my-proxy.com/api',
        includeVersionInBaseUrl: false,
        defaultModel: 'custom-model-2.5',
      );

      expect(gemini.apiKey, equals('test-api-key'));
      expect(gemini.baseURL, equals('https://my-proxy.com/api'));
      expect(gemini.includeVersionInBaseUrl, isFalse);
      expect(gemini.defaultModel, equals('custom-model-2.5'));
    });

    test('Initialization with global defaultGenerationConfig', () {
      final defaultConfig = GenerationConfig(
        maxOutputTokens: 2048,
        temperature: 0.7,
        topK: 40,
        responseMimeType: 'application/json',
      );

      final gemini = Gemini.reInitialize(
        apiKey: 'test-api-key',
        defaultModel: 'gemini-2.5-pro',
        generationConfig: defaultConfig,
      );

      expect(gemini.defaultModel, equals('gemini-2.5-pro'));
      expect(gemini.defaultGenerationConfig?.maxOutputTokens, equals(2048));
      expect(gemini.defaultGenerationConfig?.temperature, equals(0.7));
      expect(gemini.defaultGenerationConfig?.topK, equals(40));
      expect(gemini.defaultGenerationConfig?.responseMimeType,
          equals('application/json'));
    });
  });

  group('GenerationConfig Merging Logic', () {
    test(
        'GenerationConfig toJson includes responseMimeType and non-null fields',
        () {
      final config = GenerationConfig(
        temperature: 0.5,
        maxOutputTokens: 1000,
        responseMimeType: 'text/plain',
      );

      final json = config.toJson();
      expect(json['temperature'], equals(0.5));
      expect(json['maxOutputTokens'], equals(1000));
      expect(json['responseMimeType'], equals('text/plain'));
      expect(json.containsKey('stopSequences'), isFalse);
    });

    test('GenerationConfig fromJson parses responseMimeType', () {
      final json = {
        'temperature': 0.8,
        'maxOutputTokens': 500,
        'responseMimeType': 'application/json',
      };

      final config = GenerationConfig.fromJson(json);
      expect(config.temperature, equals(0.8));
      expect(config.maxOutputTokens, equals(500));
      expect(config.responseMimeType, equals('application/json'));
    });
  });

  group('Typed Exception Hierarchy', () {
    test('GeminiApiException string representation and parameters', () {
      const exception = GeminiApiException(
        'Invalid API Key',
        statusCode: 400,
        details: {'reason': 'API_KEY_INVALID'},
      );

      expect(exception, isA<GeminiException>());
      expect(exception.statusCode, equals(400));
      expect(exception.message, equals('Invalid API Key'));
      expect(exception.details, equals({'reason': 'API_KEY_INVALID'}));
      expect(exception.toString(), contains('GeminiApiException'));
      expect(exception.toString(), contains('400'));
    });

    test('GeminiNetworkException string representation and parameters', () {
      const exception = GeminiNetworkException(
        'Connection timeout',
        statusCode: 504,
      );

      expect(exception, isA<GeminiException>());
      expect(exception.statusCode, equals(504));
      expect(exception.message, equals('Connection timeout'));
      expect(exception.toString(), contains('GeminiNetworkException'));
    });

    test('GeminiConfigException string representation and parameters', () {
      const exception = GeminiConfigException(
        'Base URL cannot be empty',
      );

      expect(exception, isA<GeminiException>());
      expect(exception.message, equals('Base URL cannot be empty'));
      expect(exception.toString(), contains('GeminiConfigException'));
    });
  });
}
