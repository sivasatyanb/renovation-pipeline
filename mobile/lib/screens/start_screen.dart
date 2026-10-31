import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/call_api_client.dart';
import '../services/call_handler.dart';
import '../services/photo_picker_service.dart';
import '../services/render_api_client.dart';
import '../services/voice_input_service.dart';
import 'studio_screen.dart';

class StartScreen extends StatefulWidget {
  final Project? initialProject;
  final QuizConfig? initialQuizConfig;
  final ResearchApiClient? apiClient;
  final RenderApiClient? renderApiClient;
  final CallApiClient? callApiClient;
  final PhotoPickerService? photoPickerService;
  final VoiceInputService? voiceInputService;
  final CallAudioPlayer Function()? audioPlayerFactory;
  final CallAudioPlayer? audioPlayer;
  final OnCallPressedCallback? onCallPressed;

  const StartScreen({
    super.key,
    this.initialProject,
    this.initialQuizConfig,
    this.apiClient,
    this.renderApiClient,
    this.callApiClient,
    this.photoPickerService,
    this.voiceInputService,
    this.audioPlayerFactory,
    this.audioPlayer,
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
    _cityController = TextEditingController(text: 'Paris');
    _loadData();
  }

  Future<void> _loadData() async {
    if (widget.initialProject != null && widget.initialQuizConfig != null) {
      _project = widget.initialProject;
      _quizConfig = widget.initialQuizConfig;
      if (_project!.client.city.isNotEmpty) {
        _cityController.text = _project!.client.city;
      }
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
      if (_project!.client.city.isNotEmpty) {
        _cityController.text = _project!.client.city;
      }

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
    final trimmedCity = _cityController.text.trim();
    final chosenCity = trimmedCity.isNotEmpty ? trimmedCity : 'Paris';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudioScreen(
          city: chosenCity,
          country: _project?.client.country ?? 'France',
          initialProject: _project,
          quizConfig: _quizConfig,
          apiClient: widget.apiClient,
          renderApiClient: widget.renderApiClient,
          callApiClient: widget.callApiClient,
          photoPickerService: widget.photoPickerService,
          voiceInputService: widget.voiceInputService,
          audioPlayerFactory: widget.audioPlayerFactory,
          audioPlayer: widget.audioPlayer,
          onCallPressed: widget.onCallPressed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RenovAI'),
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
                      // Intro Card describing full unified RenovAI pipeline
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
                                'AI-Powered Renovation Pipeline',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'RenovAI guides you through the full end-to-end renovation process:',
                                style: TextStyle(fontSize: 13, color: Colors.black87),
                              ),
                              const SizedBox(height: 12),
                              _buildStepRow(
                                Icons.auto_awesome,
                                '1. Design Studio',
                                'Compare Before/After renders & formulate design briefs.',
                              ),
                              const SizedBox(height: 8),
                              _buildStepRow(
                                Icons.quiz_outlined,
                                '2. 5-Question Quiz',
                                'Tailor your budget, timeline, scope, and trust criteria.',
                              ),
                              const SizedBox(height: 8),
                              _buildStepRow(
                                Icons.travel_explore,
                                '3. Deep Research',
                                'Vet certified contractors, ratings, and price estimates.',
                              ),
                              const SizedBox(height: 8),
                              _buildStepRow(
                                Icons.phone_in_talk,
                                '4. AI Voice Negotiation',
                                'Simulate contractor negotiation & book in-person site visits.',
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_project != null) ...[
                        const SizedBox(height: 16),
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
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                ..._project!.workItems.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.check_circle_outline,
                                          size: 18,
                                          color: Colors.green,
                                        ),
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
                      ],

                      const SizedBox(height: 16),

                      // City selection
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
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              KeyedSubtree(
                                key: const Key('city_text_field'),
                                child: TextField(
                                  key: const Key('city_input_field'),
                                  controller: _cityController,
                                  decoration: const InputDecoration(
                                    labelText: 'City',
                                    hintText: 'Enter city (e.g. Paris)',
                                    prefixIcon: Icon(Icons.location_city),
                                    border: OutlineInputBorder(),
                                  ),
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
                          'Open Design Studio',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStepRow(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.3),
              children: [
                TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: subtitle),
              ],
            ),
          ),
        ),
      ],
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
