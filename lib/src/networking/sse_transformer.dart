import 'dart:async';
import 'dart:convert';

/// Parses SSE (Server-Sent Events) byte stream into [Map<String, dynamic>] objects.
///
/// Handles:
/// - `data: {...}` SSE lines (OpenAI, Anthropic, etc.)
/// - Raw JSON arrays/objects (Gemini style)
/// - Partial chunks and multi-line data
/// - `[DONE]` sentinel
///
/// Provider-agnostic — works with any SSE-compatible AI API.
Stream<Map<String, dynamic>> parseSseStream(Stream<List<int>> byteStream) {
  final controller = StreamController<Map<String, dynamic>>();
  String buffer = '';

  byteStream.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;

      if (trimmed.startsWith('data:')) {
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') return;
        if (payload.isEmpty) return;

        _tryDecodeJson(payload, controller, (json) {
          buffer = '';
          controller.add(json);
        }, onPartial: (chunk) {
          buffer += chunk;
          _tryFlushBuffer(controller,
              ref: () => buffer, setBuffer: (v) => buffer = v);
        });
      } else if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        // Raw JSON line (Gemini style)
        buffer += trimmed;
        _tryFlushBuffer(controller,
            ref: () => buffer, setBuffer: (v) => buffer = v);
      } else {
        buffer += trimmed;
        _tryFlushBuffer(controller,
            ref: () => buffer, setBuffer: (v) => buffer = v);
      }
    },
    onDone: () {
      _tryFlushBuffer(controller,
          ref: () => buffer, setBuffer: (v) => buffer = v);
      controller.close();
    },
    onError: (error) => controller.addError(error),
    cancelOnError: true,
  );

  return controller.stream;
}

/// Try to decode a JSON string. Calls [onSuccess] if it's a valid Map,
/// calls [onPartial] if decoding fails (likely partial data).
void _tryDecodeJson(
  String payload,
  StreamController<Map<String, dynamic>> controller,
  void Function(Map<String, dynamic>) onSuccess, {
  required void Function(String chunk) onPartial,
}) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      onSuccess(decoded);
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          onSuccess(item);
        }
      }
    }
  } catch (_) {
    onPartial(payload);
  }
}

/// Try to flush the accumulated buffer as JSON.
void _tryFlushBuffer(
  StreamController<Map<String, dynamic>> controller, {
  required String Function() ref,
  required void Function(String) setBuffer,
}) {
  final buf = ref();
  if (buf.trim().isEmpty) return;
  try {
    final decoded = jsonDecode(buf);
    if (decoded is Map<String, dynamic>) {
      controller.add(decoded);
      setBuffer('');
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          controller.add(item);
        }
      }
      setBuffer('');
    }
  } catch (_) {
    // Incomplete JSON — keep buffering
  }
}
