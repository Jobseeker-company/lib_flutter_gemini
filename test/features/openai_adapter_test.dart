import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gemini reInitialize with OpenAI base URL', () {
    Gemini.init(
      apiKey: 'sk-proj-testkey',
      baseURL: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4.1',
    );

    expect(Gemini.instance, isNotNull);
  });
}
