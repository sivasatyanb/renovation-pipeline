import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/models.dart';

const String defaultApiBaseUrl = kApiBaseUrl;

/// Abstract API client for the simulated negotiation call backend.
abstract class CallApiClient {
  String get baseUrl;
  Future<String> startCall(CallRequest request);
  Future<CallStatusResponse> getCallStatus(String callId, {int after = 0});
  Future<CallStatusResponse> stopCall(String callId);
  String resolveAudioUrl(String audioUrl);
}

/// Standard HTTP implementation of [CallApiClient].
class HttpCallApiClient implements CallApiClient {
  @override
  final String baseUrl;
  final http.Client client;

  HttpCallApiClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = (baseUrl ?? defaultApiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        client = client ?? http.Client();

  @override
  Future<String> startCall(CallRequest request) async {
    final uri = Uri.parse('$baseUrl/calls');
    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final callId = data['call_id'] as String?;
      if (callId == null || callId.isEmpty) {
        throw Exception('Response missing call_id: ${response.body}');
      }
      return callId;
    } else {
      throw Exception(
        'Failed to start call (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<CallStatusResponse> getCallStatus(String callId, {int after = 0}) async {
    final uri = Uri.parse('$baseUrl/calls/$callId?after=$after');
    final response = await client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CallStatusResponse.fromJson(data);
    } else {
      throw Exception(
        'Failed to get call status (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<CallStatusResponse> stopCall(String callId) async {
    final uri = Uri.parse('$baseUrl/calls/$callId/stop');
    final response = await client.post(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CallStatusResponse.fromJson(data);
    } else {
      throw Exception(
        'Failed to stop call (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  String resolveAudioUrl(String audioUrl) {
    if (audioUrl.startsWith('http://') || audioUrl.startsWith('https://')) {
      return audioUrl;
    }
    final cleanPath = audioUrl.startsWith('/') ? audioUrl : '/$audioUrl';
    return '$baseUrl$cleanPath';
  }
}
