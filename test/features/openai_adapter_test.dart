import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAI Adapter Integration', () {
    test('Gemini reInitialize with OpenAI base URL and default model', () {
      final gemini = Gemini.reInitialize(
        apiKey: 'sk-proj-testkey',
        baseURL: 'https://api.openai.com/v1',
        defaultModel: 'gpt-4o-mini',
      );

      expect(gemini.apiKey, equals('sk-proj-testkey'));
      expect(gemini.baseURL, equals('https://api.openai.com/v1'));
      expect(gemini.defaultModel, equals('gpt-4o-mini'));
    });

    test('Gemini reInitialize with custom OpenAI proxy and responses endpoint', () {
      final gemini = Gemini.reInitialize(
        apiKey: 'sk-proxy-key',
        baseURL: 'https://my-proxy.com/v1/responses',
        defaultModel: 'gpt-4o',
      );

      expect(gemini.baseURL, equals('https://my-proxy.com/v1/responses'));
      expect(gemini.defaultModel, equals('gpt-4o'));
    });
  });
}
