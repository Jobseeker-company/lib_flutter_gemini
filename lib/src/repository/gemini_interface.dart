import 'dart:async';
import 'dart:typed_data';
import '../../flutter_gemini.dart';

abstract class GeminiInterface {
  /// [listModels]
  Future<List<GeminiModel>> listModels({TimeoutConfig? timeoutConfig});

  /// [info]
  Future<GeminiModel> info(
      {required String model, TimeoutConfig? timeoutConfig});

  /// [text]
  @Deprecated('Please use the `prompt` or `promptStream` method')
  Future<Candidates?> text(
    String text, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });

  /// [batchEmbedContents]
  Future<List<List<num>?>?> batchEmbedContents(
    List<String> texts, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });

  /// [embedContent]
  Future<List<num>?> embedContent(
    String text, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });

  /// [countTokens]
  Future<int?> countTokens(
    String text, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });

  /// [streamGenerateContent]
  @Deprecated('Please use the `prompt` or `promptStream` method')
  Stream<Candidates> streamGenerateContent(
    String text, {
    List<Uint8List>? images,
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });

  @Deprecated('Please use the `prompt` or `promptStream` method')
  Stream<Candidates> streamChat(
    List<Content> chats, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });

  /// [chat]
  @Deprecated('Please use the `prompt` or `promptStream` method')
  Future<Candidates?> chat(
    List<Content> chats, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    String? systemPrompt,
    TimeoutConfig? timeoutConfig,
  });

  /// [textAndImage]
  Future<Candidates?> textAndImage({
    required String text,
    required List<Uint8List> images,
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });

  // cancel request
  Future<void> cancelRequest();

  /// [prompt]
  Future<Candidates?> prompt({
    required List<Part> parts,
    String? model,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });

  /// [promptStream]
  Stream<Candidates?> promptStream({
    required List<Part> parts,
    String? model,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  });
}
