import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/call_api_client.dart';
import '../services/call_handler.dart';
import 'research_screen.dart';

class QuizScreen extends StatefulWidget {
  final Project? project;
  final Project? initialProject;
  final QuizConfig? quizConfig;
  final String? afterRenderUrl;
  final ResearchApiClient? apiClient;
  final CallApiClient? callApiClient;
  final CallAudioPlayer? audioPlayer;
  final OnCallPressedCallback? onCallPressed;

  const QuizScreen({
    super.key,
    this.project,
    this.initialProject,
    this.quizConfig,
    this.afterRenderUrl,
    this.apiClient,
    this.callApiClient,
    this.audioPlayer,
    this.onCallPressed,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentIndex = 0;
  Project? _effectiveProject;
  QuizConfig? _effectiveQuizConfig;
  bool _isLoading = true;

  // Stored selections for each question ID
  final Map<String, String> _singleAnswers = {};
  final Set<String> _selectedTrustRequirements = {};

  List<QuizQuestion> get _questions => _effectiveQuizConfig?.questions ?? [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final providedProject = widget.initialProject ?? widget.project;
    if (providedProject != null && widget.quizConfig != null) {
      _effectiveProject = providedProject;
      _effectiveQuizConfig = widget.quizConfig;
      setState(() => _isLoading = false);
      return;
    }

    try {
      Project? proj = providedProject;
      if (proj == null) {
        final projectJson =
            await rootBundle.loadString('assets/shared/fixtures/demo_project.json');
        proj = Project.fromJson(jsonDecode(projectJson) as Map<String, dynamic>);
      }

      QuizConfig? cfg = widget.quizConfig;
      if (cfg == null) {
        final quizJson =
            await rootBundle.loadString('assets/shared/quiz_questions.json');
        cfg = QuizConfig.fromJson(jsonDecode(quizJson) as Map<String, dynamic>);
      }

      setState(() {
        _effectiveProject = proj;
        _effectiveQuizConfig = cfg;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to initialize quiz data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onBackPressed() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onNextPressed() {
    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  void _onSubmit() {
    if (_effectiveProject == null) return;

    final answers = QuizAnswers(
      budget: _singleAnswers['budget'] ?? '',
      scope: _singleAnswers['scope'] ?? '',
      timeline: _singleAnswers['timeline'] ?? '',
      priority: _singleAnswers['priority'] ?? '',
      trustRequirements: _selectedTrustRequirements.toList(),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResearchScreen(
          project: _effectiveProject!,
          answers: answers,
          afterRenderUrl: widget.afterRenderUrl,
          apiClient: widget.apiClient,
          callApiClient: widget.callApiClient,
          audioPlayer: widget.audioPlayer,
          onCallPressed: widget.onCallPressed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_questions.isEmpty || _effectiveProject == null || _effectiveQuizConfig == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: const Center(child: Text('No quiz questions configured.')),
      );
    }

    final question = _questions[_currentIndex];
    final currencyInfo =
        _effectiveQuizConfig!.getCurrency(_effectiveProject!.client.country);
    final isLastQuestion = _currentIndex == _questions.length - 1;

    final bool canProceed;
    if (question.isMultiSelect) {
      canProceed = _selectedTrustRequirements.length >= question.minSelections;
    } else {
      canProceed = _singleAnswers[question.id] != null;
    }

    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('quiz_back_button'),
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBackPressed,
        ),
        title: Text('Question ${_currentIndex + 1} of ${_questions.length}'),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6.0),
          child: LinearProgressIndicator(
            value: (_currentIndex + 1) / _questions.length,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                question.question,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              if (question.isMultiSelect)
                const Text(
                  'Select at least one requirement',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: question.options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final option = question.options[index];
                    final formattedLabel = question.usesCurrencySymbol
                        ? option.getFormattedLabel(currencyInfo.symbol)
                        : option.labelTemplate;

                    if (question.isMultiSelect) {
                      final isSelected =
                          _selectedTrustRequirements.contains(option.value);
                      return InkWell(
                        key: Key('option_${option.value}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedTrustRequirements.remove(option.value);
                            } else {
                              _selectedTrustRequirements.add(option.value);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 14.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isSelected
                                ? primaryColor.withValues(alpha: 0.08)
                                : Colors.white,
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                color: isSelected
                                    ? primaryColor
                                    : Colors.grey.shade500,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  formattedLabel,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.black87
                                        : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      final isSelected =
                          _singleAnswers[question.id] == option.value;
                      return InkWell(
                        key: Key('option_${option.value}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            _singleAnswers[question.id] = option.value;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 14.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isSelected
                                ? primaryColor.withValues(alpha: 0.08)
                                : Colors.white,
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: isSelected
                                    ? primaryColor
                                    : Colors.grey.shade500,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  formattedLabel,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.black87
                                        : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: Key(isLastQuestion ? 'submit_quiz_button' : 'next_quiz_button'),
                onPressed: canProceed
                    ? (isLastQuestion ? _onSubmit : _onNextPressed)
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  isLastQuestion ? 'Find Renovators' : 'Next',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
