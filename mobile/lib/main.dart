import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'models/models.dart';
import 'screens/details_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/research_screen.dart';
import 'screens/results_screen.dart';
import 'screens/start_screen.dart';
import 'services/api_client.dart';
import 'services/call_handler.dart';

void main() {
  runApp(const RenovationApp());
}

class RenovationApp extends StatelessWidget {
  final Project? initialProject;
  final QuizConfig? initialQuizConfig;
  final ResearchApiClient? apiClient;
  final OnCallPressedCallback? onCallPressed;

  const RenovationApp({
    super.key,
    this.initialProject,
    this.initialQuizConfig,
    this.apiClient,
    this.onCallPressed,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenovAI - Contractor Vetting',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: _InitialScreenRouter(
        initialProject: initialProject,
        initialQuizConfig: initialQuizConfig,
        apiClient: apiClient,
        onCallPressed: onCallPressed,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _InitialScreenRouter extends StatelessWidget {
  final Project? initialProject;
  final QuizConfig? initialQuizConfig;
  final ResearchApiClient? apiClient;
  final OnCallPressedCallback? onCallPressed;

  const _InitialScreenRouter({
    this.initialProject,
    this.initialQuizConfig,
    this.apiClient,
    this.onCallPressed,
  });

  String _getRequestedScreen() {
    try {
      final uri = Uri.base;
      final screenParam = uri.queryParameters['screen']?.toLowerCase();
      if (screenParam != null && screenParam.isNotEmpty) {
        return screenParam;
      }
      final fragment = uri.fragment.toLowerCase().replaceAll('/', '');
      if (fragment.isNotEmpty) {
        return fragment;
      }
    } catch (_) {}
    return 'start';
  }

  Future<Map<String, dynamic>> _loadData() async {
    final projectJsonString = await rootBundle
        .loadString('assets/shared/fixtures/demo_project.json');
    final quizJsonString =
        await rootBundle.loadString('assets/shared/quiz_questions.json');
    final resultJsonString =
        await rootBundle.loadString('assets/shared/fixtures/demo_result.json');

    final project =
        Project.fromJson(jsonDecode(projectJsonString) as Map<String, dynamic>);
    final quizConfig =
        QuizConfig.fromJson(jsonDecode(quizJsonString) as Map<String, dynamic>);
    final result = ResearchResult.fromJson(
        jsonDecode(resultJsonString) as Map<String, dynamic>);

    return {
      'project': project,
      'quizConfig': quizConfig,
      'result': result,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (initialProject != null && initialQuizConfig != null) {
      return StartScreen(
        initialProject: initialProject,
        initialQuizConfig: initialQuizConfig,
        apiClient: apiClient,
        onCallPressed: onCallPressed,
      );
    }

    final requestedScreen = _getRequestedScreen();
    if (requestedScreen == 'start') {
      return StartScreen(
        initialProject: initialProject,
        initialQuizConfig: initialQuizConfig,
        apiClient: apiClient,
        onCallPressed: onCallPressed,
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _loadData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final data = snapshot.data!;
        final project = data['project'] as Project;
        final quizConfig = data['quizConfig'] as QuizConfig;
        final result = data['result'] as ResearchResult;

        switch (requestedScreen) {
          case 'quiz':
            return QuizScreen(
              project: project,
              quizConfig: quizConfig,
              apiClient: apiClient,
              onCallPressed: onCallPressed,
            );
          case 'research':
            return ResearchScreen(
              project: project,
              answers: QuizAnswers(
                budget: '5k_15k',
                scope: 'partial',
                timeline: 'one_to_three_months',
                priority: 'balanced',
                trustRequirements: ['licensed_insured', 'style_portfolio'],
              ),
              apiClient: apiClient,
              onCallPressed: onCallPressed,
            );
          case 'results':
            return ResultsScreen(
              result: result,
              onCallPressed: onCallPressed,
            );
          case 'details':
            final contractor = result.contractors.length > 1
                ? result.contractors[1]
                : result.contractors.first;
            return DetailsScreen(
              contractor: contractor,
              onCallPressed: onCallPressed,
            );
          default:
            return StartScreen(
              initialProject: initialProject,
              initialQuizConfig: initialQuizConfig,
              apiClient: apiClient,
              onCallPressed: onCallPressed,
            );
        }
      },
    );
  }
}
