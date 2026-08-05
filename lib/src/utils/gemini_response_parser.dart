import 'dart:convert';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter_gemini/src/init.dart';
import 'package:flutter_gemini/src/models/candidates/candidates.dart';
import 'package:flutter_gemini/src/models/content/content.dart';
import 'package:flutter_gemini/src/models/gemini_response/gemini_response.dart';
import 'package:flutter_gemini/src/models/part/part.dart';
import 'package:flutter_gemini/src/utils/candidate_extension.dart';

class GeminiResponseParser {
  static const _splitter = LineSplitter();

  static Candidates? parseGenerateResponse(Map<String, dynamic> responseData) {
    if (responseData.containsKey('output_text') &&
        responseData['output_text'] != null) {
      return Candidates(
        content: Content(
          parts: [Part.text(responseData['output_text'].toString())],
          role: 'model',
        ),
      );
    }
    if (responseData.containsKey('output') && responseData['output'] is List) {
      final outputs = responseData['output'] as List;
      final textParts = <String>[];
      for (final item in outputs) {
        if (item is Map<String, dynamic> && item['content'] is List) {
          final contents = item['content'] as List;
          for (final c in contents) {
            if (c is Map<String, dynamic> && c['text'] != null) {
              textParts.add(c['text'].toString());
            }
          }
        }
      }
      if (textParts.isNotEmpty) {
        return Candidates(
          content: Content(
            parts: [Part.text(textParts.join('\n'))],
            role: 'model',
          ),
        );
      }
    }
    if (responseData.containsKey('choices')) {
      final choices = responseData['choices'] as List?;
      final choice = choices?.firstOrNull;
      final message = choice?['message'];
      final contentText =
          message?['content'] ?? choice?['delta']?['content'] ?? '';
      return Candidates(
        content: Content(
          parts: [Part.text(contentText.toString())],
          role: 'model',
        ),
      );
    }
    return GeminiResponse.fromJson(responseData).candidates?.lastOrNull;
  }

  static List<List<num>?>? parseBatchEmbeddingResponse(
      Map<String, dynamic> responseData) {
    return (responseData['embeddings'] as List)
        .map((e) => (e['values'] as List).cast<num>())
        .toList();
  }

  static Stream<Candidates> processStreamResponse(
      ResponseBody responseBody) async* {
    int index = 0;
    String modelStr = '';
    List<int> cacheUnits = [];

    try {
      await for (final itemList in responseBody.stream) {
        final list = cacheUnits + itemList;
        cacheUnits.clear();

        String res;
        try {
          res = utf8.decode(list);
        } catch (e) {
          log('Error in parsing chunk', error: e, name: 'Gemini_Exception');
          cacheUnits = list;
          continue;
        }

        res = _cleanStreamResponse(res, index == 0);
        yield* _parseStreamLines(
            res, modelStr, (newModelStr) => modelStr = newModelStr);
        index++;
      }
    } catch (e) {
      // Swallow expected stream-end exceptions (cancel, connection closed) so
      // the stream completes normally instead of propagating an error.
      log('Stream ended with: $e', name: 'Gemini_Stream');
    }
  }

  static Stream<Candidates> _parseStreamLines(String response,
      String currentModelStr, void Function(String) updateModelStr) async* {
    String modelStr = currentModelStr;
    for (final rawLine in _splitter.convert(response)) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('event:')) continue;
      if (line.startsWith('data:')) {
        line = line.substring(5).trim();
      }
      if (line == '[DONE]') {
        modelStr = '';
        continue;
      }
      if (modelStr.isEmpty && line == ',') continue;
      modelStr += line;

      final candidate = _tryParseCandidate(modelStr);
      if (candidate != null) {
        yield candidate;
        Gemini.instance.typeProvider?.add(candidate.output);
        modelStr = '';
      }
    }
    updateModelStr(modelStr);
  }

  static Candidates? _tryParseCandidate(String jsonStr) {
    try {
      String clean = jsonStr.trim();
      if (clean.startsWith('data:')) {
        clean = clean.substring(5).trim();
      }
      if (clean == '[DONE]') return null;

      final decoded = jsonDecode(clean);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('candidates')) {
          final candidateData = (decoded['candidates'] as List?)?.firstOrNull;
          return candidateData != null
              ? Candidates.fromJson(candidateData)
              : null;
        }
        if (decoded.containsKey('output_text') &&
            decoded['output_text'] != null) {
          return Candidates(
            content: Content(
              parts: [Part.text(decoded['output_text'].toString())],
              role: 'model',
            ),
          );
        }
        if (decoded.containsKey('delta')) {
          final deltaVal = decoded['delta'];
          String? deltaText;
          if (deltaVal is String) {
            deltaText = deltaVal;
          } else if (deltaVal is Map) {
            deltaText =
                deltaVal['text']?.toString() ?? deltaVal['content']?.toString();
          }
          if (deltaText != null && deltaText.isNotEmpty) {
            return Candidates(
              content: Content(
                parts: [Part.text(deltaText)],
                role: 'model',
              ),
            );
          }
        }
        if (decoded.containsKey('choices')) {
          final choice = (decoded['choices'] as List?)?.firstOrNull;
          final contentText =
              choice?['delta']?['content'] ?? choice?['message']?['content'];
          if (contentText != null && contentText.toString().isNotEmpty) {
            return Candidates(
              content: Content(
                parts: [Part.text(contentText.toString())],
                role: 'model',
              ),
            );
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static String _cleanStreamResponse(String response, bool isFirst) {
    String cleaned = response.trim();
    if (isFirst && cleaned.startsWith('[')) cleaned = cleaned.substring(1);
    if (cleaned.startsWith(',')) cleaned = cleaned.substring(1);
    if (cleaned.endsWith(']')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned.trim();
  }
}
