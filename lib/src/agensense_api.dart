import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

typedef ChatDeltaHandler = void Function(String delta);

class AppConfig {
  const AppConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.providerProfileId,
    required this.clientId,
    required this.deviceLabel,
    required this.sampleRateHz,
    required this.channels,
  });

  final String baseUrl;
  final String apiKey;
  final String providerProfileId;
  final String clientId;
  final String deviceLabel;
  final int sampleRateHz;
  final int channels;

  String get normalizedBaseUrl {
    final trimmed = baseUrl.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}

class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.namespace,
    this.name = '',
    this.asrBaseUrl = '',
    this.asrModel = '',
    this.llmBaseUrl = '',
    this.llmModel = '',
    this.ttsBaseUrl = '',
    this.ttsModel = '',
    this.vadBaseUrl = '',
    this.vadModel = '',
    this.isDefault = false,
  });

  factory ProviderProfile.fromJson(Map<String, dynamic> json) {
    return ProviderProfile(
      id: stringValue(json['id']),
      namespace: stringValue(json['namespace']),
      name: stringValue(json['name']),
      asrBaseUrl: stringValue(json['asr_base_url']),
      asrModel: stringValue(json['asr_model']),
      llmBaseUrl: stringValue(json['llm_base_url']),
      llmModel: stringValue(json['llm_model']),
      ttsBaseUrl: stringValue(json['tts_base_url']),
      ttsModel: stringValue(json['tts_model']),
      vadBaseUrl: stringValue(json['vad_base_url']),
      vadModel: stringValue(json['vad_model']),
      isDefault: json['default'] == true,
    );
  }

  final String id;
  final String namespace;
  final String name;
  final String asrBaseUrl;
  final String asrModel;
  final String llmBaseUrl;
  final String llmModel;
  final String ttsBaseUrl;
  final String ttsModel;
  final String vadBaseUrl;
  final String vadModel;
  final bool isDefault;
}

class ChatResponse {
  const ChatResponse({
    required this.providerProfileId,
    required this.text,
    required this.raw,
    this.deltas = const <String>[],
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      providerProfileId: stringValue(json['provider_profile_id']),
      text: stringValue(json['text']),
      deltas: listOfString(json['deltas']),
      raw: json,
    );
  }

  final String providerProfileId;
  final String text;
  final List<String> deltas;
  final Map<String, dynamic> raw;
}

class TTSResponse {
  const TTSResponse({
    required this.providerProfileId,
    required this.codec,
    required this.sampleRateHz,
    required this.channels,
    required this.audio,
    required this.chunkCount,
    required this.raw,
  });

  factory TTSResponse.fromJson(Map<String, dynamic> json) {
    final format = asMap(json['format']);
    return TTSResponse(
      providerProfileId: stringValue(json['provider_profile_id']),
      codec: stringValue(format['codec'], fallback: 'pcm_s16le'),
      sampleRateHz: intValue(format['sample_rate_hz'], fallback: 16000),
      channels: intValue(format['channels'], fallback: 1),
      audio: base64Decode(stringValue(json['audio_base64'])),
      chunkCount: intValue(json['chunk_count']),
      raw: json,
    );
  }

  final String providerProfileId;
  final String codec;
  final int sampleRateHz;
  final int channels;
  final Uint8List audio;
  final int chunkCount;
  final Map<String, dynamic> raw;
}

class AgenSenseApi {
  AgenSenseApi(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  final AppConfig config;
  final http.Client _client;

  Future<Map<String, dynamic>> health() async {
    final response = await _client
        .get(_uri('/healthz'))
        .timeout(const Duration(seconds: 10));
    return _decode(response);
  }

  Future<List<ProviderProfile>> listProviders() async {
    final response = await _client
        .get(_uri('/v1/providers'), headers: _authHeaders())
        .timeout(const Duration(seconds: 20));
    final json = _decode(response);
    final items = json['items'];
    if (items is! List) {
      return const <ProviderProfile>[];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(ProviderProfile.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> upsertProvider(Map<String, dynamic> body) async {
    final response = await _client
        .post(
          _uri('/v1/providers'),
          headers: _jsonHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  Future<ChatResponse> chat({
    required List<Map<String, String>> messages,
    Map<String, dynamic>? voiceAssistant,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _client
        .post(
          _uri('/v1/llm/chat'),
          headers: _jsonHeaders(),
          body: jsonEncode(
            _chatBody(
              messages: messages,
              voiceAssistant: voiceAssistant,
              metadata: metadata,
            ),
          ),
        )
        .timeout(const Duration(seconds: 90));
    return ChatResponse.fromJson(_decode(response));
  }

  Future<ChatResponse> chatStream({
    required List<Map<String, String>> messages,
    Map<String, dynamic>? voiceAssistant,
    Map<String, dynamic>? metadata,
    ChatDeltaHandler? onDelta,
  }) async {
    final body = <String, dynamic>{
      ..._chatBody(
        messages: messages,
        voiceAssistant: voiceAssistant,
        metadata: metadata,
      ),
    };
    final request = http.Request('POST', _uri('/v1/llm/chat/stream'))
      ..headers.addAll({..._jsonHeaders(), 'accept': 'text/event-stream'})
      ..body = jsonEncode(body);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = (await response.stream.bytesToString()).trim();
      final message = _errorMessage(errorBody);
      throw AgenSenseApiException(response.statusCode, message);
    }

    var eventName = '';
    final dataLines = <String>[];
    final deltas = <String>[];
    final text = StringBuffer();
    ChatResponse? done;

    void flushEvent() {
      if (dataLines.isEmpty) {
        eventName = '';
        return;
      }
      final rawData = dataLines.join('\n');
      final json = jsonDecode(rawData) as Map<String, dynamic>;
      switch (eventName) {
        case 'delta':
          final delta = stringValue(json['text']);
          if (delta.isNotEmpty) {
            deltas.add(delta);
            text.write(delta);
            onDelta?.call(delta);
          }
          break;
        case 'done':
          done = ChatResponse.fromJson(json);
          break;
        case 'error':
          throw AgenSenseApiException(
            response.statusCode,
            stringValue(json['error'], fallback: rawData),
          );
        default:
          break;
      }
      eventName = '';
      dataLines.clear();
    }

    await for (final rawLine
        in utf8.decoder.bind(response.stream).transform(const LineSplitter())) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        flushEvent();
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring('event:'.length).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring('data:'.length).trimLeft());
      }
    }
    flushEvent();

    return done ??
        ChatResponse(
          providerProfileId: config.providerProfileId.trim(),
          text: text.toString().trim(),
          deltas: deltas,
          raw: {
            'provider_profile_id': config.providerProfileId.trim(),
            'text': text.toString().trim(),
            'deltas': deltas,
          },
        );
  }

  Map<String, dynamic> _chatBody({
    required List<Map<String, String>> messages,
    Map<String, dynamic>? voiceAssistant,
    Map<String, dynamic>? metadata,
  }) {
    return <String, dynamic>{
      'provider_profile_id': config.providerProfileId.trim(),
      'client_id': config.clientId.trim(),
      'device_label': config.deviceLabel.trim(),
      'session_id': newSessionId('chat'),
      'messages': messages,
      ...?voiceAssistant == null
          ? null
          : <String, dynamic>{'voice_assistant': voiceAssistant},
      ...?metadata == null ? null : <String, dynamic>{'metadata': metadata},
    };
  }

  Future<Map<String, dynamic>> transcribe(Uint8List pcmAudio) async {
    final body = <String, dynamic>{
      'provider_profile_id': config.providerProfileId.trim(),
      'client_id': config.clientId.trim(),
      'device_label': config.deviceLabel.trim(),
      'session_id': newSessionId('asr'),
      'format': audioFormat(config),
      'audio_base64': base64Encode(pcmAudio),
    };
    final response = await _client
        .post(
          _uri('/v1/asr/transcribe'),
          headers: _jsonHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));
    return _decode(response);
  }

  Future<TTSResponse> synthesize(String text) async {
    final body = <String, dynamic>{
      'provider_profile_id': config.providerProfileId.trim(),
      'client_id': config.clientId.trim(),
      'device_label': config.deviceLabel.trim(),
      'session_id': newSessionId('tts'),
      'text': text,
      'format': audioFormat(config),
    };
    final response = await _client
        .post(
          _uri('/v1/tts/synthesize'),
          headers: _jsonHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));
    return TTSResponse.fromJson(_decode(response));
  }

  Future<Map<String, dynamic>> bootstrap(Map<String, dynamic> body) async {
    final response = await _client
        .post(
          _uri('/v1/bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  Future<Map<String, dynamic>> deviceConfig({
    required String deviceId,
    required String token,
  }) async {
    final response = await _client
        .get(
          _uri('/v1/device/config'),
          headers: {'authorization': 'Bearer $token', 'x-device-id': deviceId},
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> sendTelemetry({
    required String deviceId,
    required String token,
    required Map<String, dynamic> telemetry,
  }) async {
    final response = await _client
        .post(
          _uri('/v1/device/telemetry'),
          headers: {
            'authorization': 'Bearer $token',
            'x-device-id': deviceId,
            'content-type': 'application/json',
          },
          body: jsonEncode(telemetry),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<List<Map<String, dynamic>>> traces() async {
    final response = await _client
        .get(_uri('/debug/api/traces'))
        .timeout(const Duration(seconds: 20));
    final json = _decode(response);
    final items = json['items'];
    if (items is! List) {
      return const <Map<String, dynamic>>[];
    }
    return items.whereType<Map<String, dynamic>>().toList();
  }

  Uri _uri(String path) => Uri.parse('${config.normalizedBaseUrl}$path');

  Map<String, String> _authHeaders() => {
    'authorization': 'Bearer ${config.apiKey.trim()}',
  };

  Map<String, String> _jsonHeaders() => {
    ..._authHeaders(),
    'content-type': 'application/json',
  };

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.trim();
    final json = body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = stringValue(json['error'], fallback: response.body);
      throw AgenSenseApiException(response.statusCode, message);
    }
    return json;
  }

  String _errorMessage(String body) {
    if (body.isEmpty) {
      return '';
    }
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return stringValue(json['error'], fallback: body);
    } catch (_) {
      return body;
    }
  }
}

class AgenSenseApiException implements Exception {
  const AgenSenseApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'HTTP $statusCode: $message';
}

Map<String, dynamic> audioFormat(AppConfig config) => {
  'codec': 'pcm_s16le',
  'sample_rate_hz': config.sampleRateHz,
  'channels': config.channels,
};

String newSessionId(String prefix) {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  return '$prefix-$stamp';
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

String stringValue(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

int intValue(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> listOfString(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList();
}
