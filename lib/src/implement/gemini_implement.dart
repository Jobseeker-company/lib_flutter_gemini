import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_gemini/src/config/constants.dart';
import 'package:flutter_gemini/src/utils/gemini_data_builder.dart';
import 'package:flutter_gemini/src/utils/gemini_model_manager.dart';
import 'package:flutter_gemini/src/utils/gemini_request_handler.dart';
import 'package:flutter_gemini/src/utils/gemini_response_parser.dart';
import 'package:flutter_gemini/src/repository/gemini_interface.dart';
import 'gemini_service.dart';

/// [GeminiImpl]
/// In this class we declare and implement all the functions body
class GeminiImpl implements GeminiInterface {
  final GeminiService _api;
  final GeminiRequestHandler _requestHandler;
  final GeminiModelManager _modelManager;
  final String? defaultModel;
  final GenerationConfig? defaultGenerationConfig;

  GeminiImpl({
    required GeminiService api,
    this.defaultModel,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
  })  : _api = api,
        defaultGenerationConfig = generationConfig,
        _requestHandler = GeminiRequestHandler(api),
        _modelManager = GeminiModelManager(api) {
    _api
      ..safetySettings = safetySettings
      ..generationConfig = generationConfig;
  }

  Future<String> resolveModelName(
      String? userModel, String expectedModel) async {
    return _modelManager.resolveModelName(
      userModel: userModel,
      defaultModel: defaultModel,
      expectedModel: expectedModel,
    );
  }

  GenerationConfig? mergeGenerationConfig(GenerationConfig? requestConfig) {
    if (defaultGenerationConfig == null) return requestConfig;
    if (requestConfig == null) return defaultGenerationConfig;

    return GenerationConfig(
      stopSequences:
          requestConfig.stopSequences ?? defaultGenerationConfig?.stopSequences,
      temperature:
          requestConfig.temperature ?? defaultGenerationConfig?.temperature,
      maxOutputTokens: requestConfig.maxOutputTokens ??
          defaultGenerationConfig?.maxOutputTokens,
      topP: requestConfig.topP ?? defaultGenerationConfig?.topP,
      topK: requestConfig.topK ?? defaultGenerationConfig?.topK,
      responseMimeType: requestConfig.responseMimeType ??
          defaultGenerationConfig?.responseMimeType,
    );
  }

  @override
  Future<List<List<num>?>?> batchEmbedContents(
    List<String> texts, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async {
    final resolvedModel = await resolveModelName(modelName, 'embedding-001');
    final mergedConfig = mergeGenerationConfig(generationConfig);
    return _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:batchEmbedContents',
      data: GeminiDataBuilder.buildBatchEmbedData(texts),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
      responseParser: GeminiResponseParser.parseBatchEmbeddingResponse,
    );
  }

  @override
  Future<Candidates?> chat(
    List<Content> chats, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
    String? systemPrompt,
  }) async {
    final resolvedModel =
        await resolveModelName(modelName, Constants.defaultModel);
    final mergedConfig = mergeGenerationConfig(generationConfig);
    return _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:${Constants.defaultGenerateType}',
      data: GeminiDataBuilder.buildChatData(chats, systemPrompt),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
      responseParser: GeminiResponseParser.parseGenerateResponse,
    );
  }

  @override
  Future<int?> countTokens(
    String text, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async {
    final resolvedModel =
        await resolveModelName(modelName, Constants.defaultModel);
    final mergedConfig = mergeGenerationConfig(generationConfig);
    return _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:countTokens',
      data: GeminiDataBuilder.buildTextData(text),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
      responseParser: (data) => data['totalTokens'],
    );
  }

  @override
  Future<List<num>?> embedContent(
    String text, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async {
    final resolvedModel = await resolveModelName(modelName, 'embedding-001');
    final mergedConfig = mergeGenerationConfig(generationConfig);
    return _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:embedContent',
      data: GeminiDataBuilder.buildEmbedData(text),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
      responseParser: (data) =>
          (data['embedding']['values'] as List).cast<num>(),
    );
  }

  @override
  Future<GeminiModel> info(
      {required String model, TimeoutConfig? timeoutConfig}) async {
    final route = model.startsWith('models/') ? model : 'models/$model';
    return _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: route,
      isGetRequest: true,
      responseParser: (data) => GeminiModel.fromJson(data),
    );
  }

  @override
  Future<List<GeminiModel>> listModels({TimeoutConfig? timeoutConfig}) async {
    return _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: 'models',
      isGetRequest: true,
      responseParser: (data) => GeminiModel.jsonToList(data['models']),
    );
  }

  @override
  Future<Candidates?> text(
    String text, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async {
    final resolvedModel =
        await resolveModelName(modelName, Constants.defaultModel);
    final mergedConfig = mergeGenerationConfig(generationConfig);
    final candidate = await _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:${Constants.defaultGenerateType}',
      data: GeminiDataBuilder.buildTextData(text),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
      responseParser: GeminiResponseParser.parseGenerateResponse,
    );
    Gemini.instance.typeProvider?.add(candidate?.output);
    return candidate;
  }

  @override
  Future<Candidates?> textAndImage({
    required String text,
    required List<Uint8List> images,
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async {
    final resolvedModel = await resolveModelName(modelName, 'gemini-1.5-flash');
    final mergedConfig = mergeGenerationConfig(generationConfig);
    return _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:${Constants.defaultGenerateType}',
      data: GeminiDataBuilder.buildTextAndImageData(text, images),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
      responseParser: GeminiResponseParser.parseGenerateResponse,
    );
  }

  @override
  Future<Candidates?> prompt({
    required List<Part> parts,
    String? model,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async {
    final resolvedModel = await resolveModelName(model, Constants.defaultModel);
    final mergedConfig = mergeGenerationConfig(generationConfig);
    return _requestHandler.executeRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:${Constants.defaultGenerateType}',
      data: GeminiDataBuilder.buildPromptData(parts),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
      responseParser: GeminiResponseParser.parseGenerateResponse,
    );
  }

  @override
  Stream<Candidates> streamChat(
    List<Content> chats, {
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async* {
    final resolvedModel =
        await resolveModelName(modelName, Constants.defaultModel);
    final mergedConfig = mergeGenerationConfig(generationConfig);
    yield* _requestHandler.executeStreamRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:streamGenerateContent',
      data: GeminiDataBuilder.buildChatData(chats, null),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
    );
  }

  @override
  Stream<Candidates> streamGenerateContent(
    String text, {
    List<Uint8List>? images,
    String? modelName,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async* {
    final resolvedModel =
        await resolveModelName(modelName, Constants.defaultModel);
    final mergedConfig = mergeGenerationConfig(generationConfig);
    yield* _requestHandler.executeStreamRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:streamGenerateContent',
      data: GeminiDataBuilder.buildTextAndImageData(text, images),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
    );
  }

  @override
  Stream<Candidates?> promptStream({
    required List<Part> parts,
    String? model,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    TimeoutConfig? timeoutConfig,
  }) async* {
    final resolvedModel = await resolveModelName(model, Constants.defaultModel);
    final mergedConfig = mergeGenerationConfig(generationConfig);
    yield* _requestHandler.executeStreamRequest(
      timeoutConfig: timeoutConfig,
      endpoint: '$resolvedModel:streamGenerateContent',
      data: GeminiDataBuilder.buildPromptData(parts),
      generationConfig: mergedConfig,
      safetySettings: safetySettings,
    );
  }

  @override
  Future<void> cancelRequest() => _api.cancelRequest();
}
