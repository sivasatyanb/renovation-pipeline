import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/models.dart';

/// Abstract API client for the renovation research backend.
abstract class ResearchApiClient {
  Future<String> startResearch(Project project, QuizAnswers answers);
  Future<JobStatusResponse> getResearchStatus(String jobId);
}

/// Standard HTTP implementation of [ResearchApiClient].
class HttpResearchApiClient implements ResearchApiClient {
  final String baseUrl;
  final http.Client client;

  HttpResearchApiClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = (baseUrl ?? kApiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        client = client ?? http.Client();

  @override
  Future<String> startResearch(Project project, QuizAnswers answers) async {
    final uri = Uri.parse('$baseUrl/research');
    final payload = {
      'project': project.toJson(),
      'answers': answers.toJson(),
    };

    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final jobId = data['job_id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        throw Exception('Response missing job_id: ${response.body}');
      }
      return jobId;
    } else {
      throw Exception(
        'Failed to start research (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<JobStatusResponse> getResearchStatus(String jobId) async {
    final uri = Uri.parse('$baseUrl/research/$jobId');
    final response = await client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return JobStatusResponse.fromJson(data);
    } else {
      throw Exception(
        'Failed to get status (${response.statusCode}): ${response.body}',
      );
    }
  }
}
