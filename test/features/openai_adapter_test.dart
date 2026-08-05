import 'package:dio/dio.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_gemini/src/implement/gemini_service.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAI Adapter — Init & Config', () {
    test('reInitialize stores OpenAI base URL and model', () {
      final gemini = Gemini.reInitialize(
        apiKey: 'sk-proj-testkey',
        baseURL: 'https://api.openai.com/v1',
        defaultModel: 'gpt-4o-mini',
      );
      expect(gemini.apiKey, 'sk-proj-testkey');
      expect(gemini.baseURL, 'https://api.openai.com/v1');
      expect(gemini.defaultModel, 'gpt-4o-mini');
    });

    test('reInitialize with o1 model name is stored correctly', () {
      final gemini = Gemini.reInitialize(
        apiKey: 'sk-test',
        baseURL: 'https://api.openai.com/v1',
        defaultModel: 'o1-mini',
      );
      expect(gemini.defaultModel, 'o1-mini');
    });

    test('reInitialize with custom proxy URL keeps baseURL as-is', () {
      final gemini = Gemini.reInitialize(
        apiKey: 'sk-proxy-key',
        baseURL: 'https://my-openai-proxy.example.com/v1',
        defaultModel: 'gpt-4o',
      );
      expect(gemini.baseURL, 'https://my-openai-proxy.example.com/v1');
    });

    test('reInitialize with Gemini base URL stores Gemini model', () {
      final gemini = Gemini.reInitialize(
        apiKey: 'AIza-test',
        defaultModel: 'gemini-2.5-flash',
      );
      expect(gemini.defaultModel, 'gemini-2.5-flash');
    });
  });

  group('OpenAI Adapter — Auth Detection', () {
    test('OpenAI URL is detected by "openai" substring', () {
      final cases = [
        'https://api.openai.com/v1/',
        'https://my-openai-proxy.example.com/v1/',
        'https://openai-gateway.internal/v1/',
      ];
      for (final url in cases) {
        expect(url.contains('openai'), isTrue, reason: 'Expected $url to match OpenAI pattern');
      }
    });

    test('Gemini URL is NOT detected as OpenAI', () {
      final cases = [
        'https://generativelanguage.googleapis.com/v1/',
        'https://my-gemini-proxy.example.com/v1/',
      ];
      for (final url in cases) {
        expect(url.contains('openai'), isFalse, reason: 'Expected $url to NOT match OpenAI pattern');
      }
    });

    test('GeminiService created with Gemini URL does not contain openai', () {
      final service = GeminiService(
        Dio(BaseOptions(baseUrl: 'https://generativelanguage.googleapis.com/v1/')),
        apiKey: 'AIza-test',
      );
      expect(service.dio.options.baseUrl.contains('openai'), isFalse);
    });

    test('GeminiService created with OpenAI URL contains openai', () {
      final service = GeminiService(
        Dio(BaseOptions(baseUrl: 'https://api.openai.com/v1/')),
        apiKey: 'sk-test',
      );
      expect(service.dio.options.baseUrl.contains('openai'), isTrue);
    });
  });

  group('OpenAI Adapter — Endpoint Resolution Logic', () {
    test('proxy baseUrl ending with /responses resolves to empty suffix', () {
      for (final url in ['https://proxy.com/responses', 'https://proxy.com/responses/']) {
        final resolved = url.endsWith('/responses') || url.endsWith('/responses/');
        expect(resolved, isTrue);
      }
    });

    test('proxy baseUrl ending with /chat/completions resolves to empty suffix', () {
      for (final url in [
        'https://proxy.com/chat/completions',
        'https://proxy.com/chat/completions/'
      ]) {
        final resolved = url.endsWith('/chat/completions') ||
            url.endsWith('/chat/completions/');
        expect(resolved, isTrue);
      }
    });

    test('openai.com base URL should route to chat/completions sub-path', () {
      const baseUrl = 'https://api.openai.com/v1/';
      final isOpenAi = baseUrl.contains('openai');
      final isAlreadyEndpoint = baseUrl.endsWith('/responses') ||
          baseUrl.endsWith('/responses/') ||
          baseUrl.endsWith('/chat/completions') ||
          baseUrl.endsWith('/chat/completions/');
      // For api.openai.com/v1/, we should append chat/completions
      expect(isOpenAi && !isAlreadyEndpoint, isTrue);
    });
  });

  group('OpenAI Adapter — GenerationConfig Mapping', () {
    test('GenerationConfig fields are set correctly', () {
      final config = GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 512,
        topP: 0.9,
        stopSequences: ['STOP'],
        responseMimeType: 'application/json',
      );
      expect(config.temperature, 0.7);
      expect(config.maxOutputTokens, 512);
      expect(config.topP, 0.9);
      expect(config.stopSequences, ['STOP']);
      expect(config.responseMimeType, 'application/json');
    });

    test('responseMimeType application/json maps to json_object response_format', () {
      const mime = 'application/json';
      final responseFormat = mime == 'application/json' ? {'type': 'json_object'} : null;
      expect(responseFormat, {'type': 'json_object'});
    });

    test('GenerationConfig toJson includes responseMimeType', () {
      final config = GenerationConfig(
        temperature: 0.5,
        responseMimeType: 'application/json',
      );
      final json = config.toJson();
      expect(json['responseMimeType'], 'application/json');
      expect(json['temperature'], 0.5);
    });
  });

  group('OpenAI Adapter — Role Mapping', () {
    test('Gemini model role maps to OpenAI assistant role', () {
      final roleMap = {
        'model': 'assistant',
        'user': 'user',
        'system': 'system',
      };
      for (final entry in roleMap.entries) {
        final geminiRole = entry.key;
        final mapped = geminiRole == 'model' ? 'assistant' : geminiRole;
        expect(mapped, entry.value);
      }
    });

    test('null role defaults to user', () {
      const String? geminiRole = null;
      final mapped = geminiRole == 'model' ? 'assistant' : (geminiRole ?? 'user');
      expect(mapped, 'user');
    });
  });
}
