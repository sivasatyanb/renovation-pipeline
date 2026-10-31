import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/call_handler.dart';
import 'quiz_screen.dart';

class StartScreen extends StatefulWidget {
  final Project? initialProject;
  final QuizConfig? initialQuizConfig;
  final ResearchApiClient? apiClient;
  final OnCallPressedCallback? onCallPressed;

  const StartScreen({
    super.key,
    this.initialProject,
    this.initialQuizConfig,
    this.apiClient,
    this.onCallPressed,
  });

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  Project? _project;
  QuizConfig? _quizConfig;
  late TextEditingController _cityController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _cityController = TextEditingController();
    _loadData();
  }

  Future<void> _loadData() async {
    if (widget.initialProject != null && widget.initialQuizConfig != null) {
      _project = widget.initialProject;
      _quizConfig = widget.initialQuizConfig;
      _cityController.text = _project!.client.city;
      setState(() => _isLoading = false);
      return;
    }

    try {
      final projectJsonString = await rootBundle
          .loadString('assets/shared/fixtures/demo_project.json');
      final quizJsonString =
          await rootBundle.loadString('assets/shared/quiz_questions.json');

      final projectData = jsonDecode(projectJsonString) as Map<String, dynamic>;
      final quizData = jsonDecode(quizJsonString) as Map<String, dynamic>;

      _project = widget.initialProject ?? Project.fromJson(projectData);
      _quizConfig = widget.initialQuizConfig ?? QuizConfig.fromJson(quizData);
      _cityController.text = _project!.client.city;

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load project configuration: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  void _onStartPressed() {
    if (_project == null || _quizConfig == null) return;

    final trimmedCity = _cityController.text.trim();
    final updatedProject = _project!.copyWith(
      client: _project!.client.copyWith(
        city: trimmedCity.isNotEmpty ? trimmedCity : _project!.client.city,
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(
          project: updatedProject,
          quizConfig: _quizConfig!,
          apiClient: widget.apiClient,
          onCallPressed: widget.onCallPressed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Renovation Project'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Project Summary',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                'Room Type',
                                '${_project!.room.type} (${_project!.room.surfaceM2} m²)',
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                'Style',
                                _project!.style.toUpperCase(),
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                'Country',
                                _project!.client.country,
                              ),
                              const Divider(height: 24),
                              Text(
                                'Work Items',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              ..._project!.workItems.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.check_circle_outline,
                                          size: 18, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${item.trade}: ${item.description} (${item.quantity} ${item.unit})',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Renovation Location',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Specify the target city for contractor research:',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                key: const Key('city_text_field'),
                                controller: _cityController,
                                decoration: const InputDecoration(
                                  labelText: 'City',
                                  hintText: 'Enter city (e.g. Paris)',
                                  prefixIcon: Icon(Icons.location_city),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('start_quiz_button'),
                        onPressed: _onStartPressed,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Start',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}
