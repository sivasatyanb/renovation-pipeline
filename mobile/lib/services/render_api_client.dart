import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/models.dart';

/// Abstract API client for the renovation render backend.
abstract class RenderApiClient {
  String get baseUrl;
  Future<String> createRender(RenderRequest request);
  Future<RenderStatusResponse> getRenderStatus(String renderId);
  String resolveUrl(String pathOrUrl);
}

/// Standard HTTP implementation of [RenderApiClient].
class HttpRenderApiClient implements RenderApiClient {
  @override
  final String baseUrl;
  final http.Client client;

  HttpRenderApiClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = (baseUrl ?? kApiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        client = client ?? http.Client();

  @override
  Future<String> createRender(RenderRequest request) async {
    final uri = Uri.parse('$baseUrl/renders');
    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final renderId = data['render_id'] as String?;
      if (renderId == null || renderId.isEmpty) {
        throw Exception('Response missing render_id: ${response.body}');
      }
      return renderId;
    } else {
      throw Exception(
        'Failed to create render (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<RenderStatusResponse> getRenderStatus(String renderId) async {
    final uri = Uri.parse('$baseUrl/renders/$renderId');
    final response = await client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return RenderStatusResponse.fromJson(data);
    } else {
      throw Exception(
        'Failed to get render status (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  String resolveUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final cleanPath = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return '$baseUrl$cleanPath';
  }
}
