import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:renovation_mobile/main.dart';
import 'package:renovation_mobile/models/models.dart';
import 'package:renovation_mobile/screens/details_screen.dart';
import 'package:renovation_mobile/screens/quiz_screen.dart';
import 'package:renovation_mobile/screens/research_screen.dart';
import 'package:renovation_mobile/screens/results_screen.dart';
import 'package:renovation_mobile/services/api_client.dart';

class FakeResearchApiClient implements ResearchApiClient {
  final ResearchResult result;
  final bool shouldFail;
  int startCallCount = 0;
  int pollCount = 0;
  Project? lastProject;
  QuizAnswers? lastAnswers;

  FakeResearchApiClient({
    required this.result,
    this.shouldFail = false,
  });

  @override
  Future<String> startResearch(Project project, QuizAnswers answers) async {
    startCallCount++;
    lastProject = project;
    lastAnswers = answers;
    if (shouldFail) {
      throw Exception('Network connection refused');
    }
    return 'fake-job-001';
  }

  @override
  Future<JobStatusResponse> getResearchStatus(String jobId) async {
    pollCount++;
    if (shouldFail) {
      return JobStatusResponse(
        status: 'failed',
        phase: 'researching',
        error: 'Backend failed during research',
      );
    }
    return JobStatusResponse(
      status: 'completed',
      phase: 'done',
      result: result,
    );
  }
}

class MockHttpClient extends http.BaseClient {
  final http.Response Function(http.BaseRequest request) handler;

  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  late Project demoProject;
  late QuizConfig quizConfig;
  late ResearchResult demoResult;

  setUpAll(() {
    final projectRaw =
        File('../shared/fixtures/demo_project.json').readAsStringSync();
    final quizRaw = File('../shared/quiz_questions.json').readAsStringSync();
    final resultRaw =
        File('../shared/fixtures/demo_result.json').readAsStringSync();

    demoProject =
        Project.fromJson(jsonDecode(projectRaw) as Map<String, dynamic>);
    quizConfig =
        QuizConfig.fromJson(jsonDecode(quizRaw) as Map<String, dynamic>);
    demoResult =
        ResearchResult.fromJson(jsonDecode(resultRaw) as Map<String, dynamic>);
  });

  group('Model Serialization Tests', () {
    test('Project and QuizConfig round-trip properly', () {
      final projectJson = demoProject.toJson();
      final roundTripProject = Project.fromJson(projectJson);
      expect(roundTripProject.projectId, equals(demoProject.projectId));
      expect(roundTripProject.client.city, equals('Paris'));
      expect(roundTripProject.workItems.length, equals(2));

      expect(quizConfig.questions.length, equals(5));
      expect(quizConfig.getCurrency('France').symbol, equals('€'));
      expect(quizConfig.getCurrency('United Kingdom').symbol, equals('£'));
      expect(quizConfig.getCurrency('United States').symbol, equals('\$'));
      expect(quizConfig.getCurrency('UnknownCountry').symbol, equals('€'));
    });

    test('ResearchResult parses demo_result.json accurately', () {
      expect(demoResult.isDemo, isTrue);
      expect(demoResult.priceEstimate.low, equals(6200));
      expect(demoResult.priceEstimate.high, equals(9400));
      expect(demoResult.contractors.length, equals(4));

      final first = demoResult.contractors.first;
      expect(first.rank, equals(1));
      expect(first.phoneVerified, isTrue);
      expect(first.score, equals(89));
      expect(first.subscores.fit, equals(94));
      expect(first.callBrief, isNotNull);
      expect(first.callBrief!.targetPrice, equals(7100));
    });
  });

  group('HttpResearchApiClient Unit Tests', () {
    test('startResearch sends valid request and parses job_id', () async {
      final mockClient = MockHttpClient((request) {
        expect(request.url.path, equals('/research'));
        expect(request.method, equals('POST'));
        return http.Response(jsonEncode({'job_id': 'job-abc-123'}), 200);
      });

      final apiClient = HttpResearchApiClient(
        baseUrl: 'http://test.local:8000',
        client: mockClient,
      );

      final answers = QuizAnswers(
        budget: '5k_15k',
        scope: 'partial',
        timeline: 'flexible',
        priority: 'balanced',
        trustRequirements: ['licensed_insured'],
      );

      final jobId = await apiClient.startResearch(demoProject, answers);
      expect(jobId, equals('job-abc-123'));
    });

    test('getResearchStatus parses JobStatusResponse', () async {
      final mockClient = MockHttpClient((request) {
        expect(request.url.path, equals('/research/job-abc-123'));
        expect(request.method, equals('GET'));
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'status': 'completed',
            'phase': 'done',
            'result': demoResult.toJson(),
            'error': null,
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = HttpResearchApiClient(
        baseUrl: 'http://test.local:8000',
        client: mockClient,
      );

      final statusResp = await apiClient.getResearchStatus('job-abc-123');
      expect(statusResp.isCompleted, isTrue);
      expect(statusResp.phase, equals('done'));
      expect(statusResp.result, isNotNull);
      expect(statusResp.result!.contractors.length, equals(4));
    });
  });

  group('Automated Flow Tests', () {
    testWidgets(
        '1. Start screen renders with editable city initialized to "Paris", and advances to Quiz Q1 with € currency symbol formatted in budget options',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        RenovationApp(
          initialProject: demoProject,
          initialQuizConfig: quizConfig,
        ),
      );
      await tester.pumpAndSettle();

      // Check project summary info
      expect(find.text('Project Summary'), findsOneWidget);
      expect(find.textContaining('bedroom (14 m²)'), findsOneWidget);
      expect(find.text('JAPANDI'), findsOneWidget);
      expect(find.textContaining('painting: Walls and ceiling'), findsOneWidget);

      // Verify editable city text field prefilled with "Paris"
      final cityFinder = find.byKey(const Key('city_text_field'));
      expect(cityFinder, findsOneWidget);
      expect(find.widgetWithText(TextField, 'Paris'), findsOneWidget);

      // Edit city to Lyon
      await tester.enterText(cityFinder, 'Lyon');
      await tester.pumpAndSettle();

      // Tap Start button
      final startButton = find.byKey(const Key('start_quiz_button'));
      expect(startButton, findsOneWidget);
      await tester.tap(startButton);
      await tester.pumpAndSettle();

      // Verify Quiz Screen Question 1 is visible
      expect(find.text('Question 1 of 5'), findsOneWidget);
      expect(
        find.text(
            'What is your total budget, including labour, materials and tax?'),
        findsOneWidget,
      );

      // Verify € currency symbol is correctly formatted in budget options
      expect(find.text('Under €5,000'), findsOneWidget);
      expect(find.text('€5,000-€15,000'), findsOneWidget);
      expect(find.text('€15,000-€40,000'), findsOneWidget);
      expect(find.text('Over €40,000'), findsOneWidget);
      expect(find.text('Not sure, estimate it for me'), findsOneWidget);
    });

    testWidgets(
        '2. Stepping through all 5 MCQs (Q1-Q4 single choice, Q5 multi-select requiring at least 1 option, Back button navigation)',
        (WidgetTester tester) async {
      final fakeApi = FakeResearchApiClient(result: demoResult);

      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            project: demoProject,
            quizConfig: quizConfig,
            apiClient: fakeApi,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Q1: Next button is disabled initially
      final nextBtn = find.byKey(const Key('next_quiz_button'));
      expect(tester.widget<ElevatedButton>(nextBtn).enabled, isFalse);

      // Select an option for Q1
      await tester.tap(find.byKey(const Key('option_5k_15k')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(nextBtn).enabled, isTrue);

      // Advance to Q2
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
      expect(find.text('Question 2 of 5'), findsOneWidget);
      expect(find.text('How deep should the work go?'), findsOneWidget);

      // Test Back button
      final backBtn = find.byKey(const Key('quiz_back_button'));
      await tester.tap(backBtn);
      await tester.pumpAndSettle();
      expect(find.text('Question 1 of 5'), findsOneWidget);

      // Advance back to Q2
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
      expect(find.text('Question 2 of 5'), findsOneWidget);

      // Select option for Q2
      await tester.tap(find.byKey(const Key('option_partial')));
      await tester.pumpAndSettle();
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      // Q3: Timeline
      expect(find.text('Question 3 of 5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('option_one_to_three_months')));
      await tester.pumpAndSettle();
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      // Q4: Priority
      expect(find.text('Question 4 of 5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('option_balanced')));
      await tester.pumpAndSettle();
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      // Q5: Trust requirements (Multi-select)
      expect(find.text('Question 5 of 5'), findsOneWidget);
      expect(find.text('What must a renovator have?'), findsOneWidget);

      final submitBtn = find.byKey(const Key('submit_quiz_button'));
      expect(find.text('Find Renovators'), findsOneWidget);
      // Disabled initially because minSelections = 1
      expect(tester.widget<ElevatedButton>(submitBtn).enabled, isFalse);

      // Select first option
      await tester.tap(find.byKey(const Key('option_licensed_insured')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(submitBtn).enabled, isTrue);

      // Select second option
      await tester.tap(find.byKey(const Key('option_high_reviews')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(submitBtn).enabled, isTrue);

      // Uncheck both options -> button becomes disabled again
      await tester.tap(find.byKey(const Key('option_licensed_insured')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option_high_reviews')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(submitBtn).enabled, isFalse);

      // Check one option to enable submit
      await tester.tap(find.byKey(const Key('option_style_portfolio')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(submitBtn).enabled, isTrue);
    });

    testWidgets(
        '3. Research progress screen polling -> Results screen displaying "Demo data" label, price estimate, warnings, and ranked contractor cards',
        (WidgetTester tester) async {
      final fakeApi = FakeResearchApiClient(result: demoResult);
      final answers = QuizAnswers(
        budget: '5k_15k',
        scope: 'partial',
        timeline: 'one_to_three_months',
        priority: 'balanced',
        trustRequirements: ['licensed_insured'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ResearchScreen(
            project: demoProject,
            answers: answers,
            apiClient: fakeApi,
          ),
        ),
      );

      // First pump starts the job
      await tester.pump();
      await tester.pumpAndSettle();

      // Should automatically transition to ResultsScreen
      expect(find.text('Vetted Contractors'), findsOneWidget);

      // Verify Demo data banner
      expect(find.byKey(const Key('demo_data_banner')), findsOneWidget);
      expect(find.text('Demo data'), findsOneWidget);

      // Verify Price Estimate
      expect(find.byKey(const Key('price_estimate_card')), findsOneWidget);
      expect(find.text('6200 - 9400 EUR'), findsOneWidget);

      // Verify Warnings
      expect(find.byKey(const Key('warnings_card')), findsOneWidget);
      expect(
        find.textContaining(
            'All companies, phone numbers, and URLs shown here are fictional fixtures'),
        findsOneWidget,
      );

      // Verify Top Ranked Renovators Cards
      expect(find.text('Top Ranked Renovators (4)'), findsOneWidget);
      expect(
        find.byKey(const Key('contractor_card_demo-contractor-1')),
        findsOneWidget,
      );
      expect(
        find.text('Atelier Kanso Renovations (Fictional Demo Co.)'),
        findsOneWidget,
      );
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Score: 89/100'), findsOneWidget);
      expect(find.text('Phone verified'), findsWidgets);
    });

    testWidgets(
        '3b. Research progress screen displays error and handles Retry correctly',
        (WidgetTester tester) async {
      final fakeApi =
          FakeResearchApiClient(result: demoResult, shouldFail: true);
      final answers = QuizAnswers(
        budget: '5k_15k',
        scope: 'partial',
        timeline: 'flexible',
        priority: 'balanced',
        trustRequirements: ['licensed_insured'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ResearchScreen(
            project: demoProject,
            answers: answers,
            apiClient: fakeApi,
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('An error occurred'), findsOneWidget);
      final retryBtn = find.byKey(const Key('retry_button'));
      expect(retryBtn, findsOneWidget);

      await tester.tap(retryBtn);
      await tester.pump();
      expect(fakeApi.startCallCount, equals(2));
    });

    testWidgets(
        '4. Pressing the Call button logs the contractor ID via onCallPressed and does not launch any phone intent',
        (WidgetTester tester) async {
      String? calledContractorId;

      await tester.pumpWidget(
        MaterialApp(
          home: ResultsScreen(
            result: demoResult,
            onCallPressed: (contractor) {
              calledContractorId = contractor.id;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final callBtn = find.byKey(const Key('call_button_demo-contractor-1'));
      expect(callBtn, findsOneWidget);

      await tester.ensureVisible(callBtn);
      await tester.tap(callBtn);
      await tester.pumpAndSettle();

      // Verify onCallPressed was invoked with the exact contractor ID
      expect(calledContractorId, equals('demo-contractor-1'));
    });

    testWidgets(
        '5. Opening Details screen displays red flags, subscores, call brief, and source links',
        (WidgetTester tester) async {
      // Contractor 2 has red flags and call brief
      final contractorWithFlags = demoResult.contractors[1];
      expect(contractorWithFlags.redFlags.isNotEmpty, isTrue);

      String? detailsCallId;

      await tester.pumpWidget(
        MaterialApp(
          home: DetailsScreen(
            contractor: contractorWithFlags,
            onCallPressed: (c) => detailsCallId = c.id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Subscores breakdown
      expect(find.byKey(const Key('subscores_card')), findsOneWidget);
      expect(find.text('90/100'), findsOneWidget); // price
      expect(find.text('86/100'), findsOneWidget); // reputation
      expect(find.text('80/100'), findsOneWidget); // fit
      expect(find.text('85/100'), findsOneWidget); // availability

      // Red flags
      expect(find.byKey(const Key('red_flags_card')), findsOneWidget);
      expect(
        find.textContaining(
            'Portfolio shows mostly classic Haussmannian projects'),
        findsOneWidget,
      );

      // Call brief
      expect(find.byKey(const Key('call_brief_card')), findsOneWidget);
      expect(find.text('Target: €6300'), findsOneWidget);
      expect(find.text('Max: €7400'), findsOneWidget);
      expect(
        find.textContaining('Standardized 38 m2 wall/ceiling area'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            'Do you offer brushed matte invisible varnish for a natural Japandi oak finish?'),
        findsOneWidget,
      );

      // Links
      expect(find.text('Phone Source URL'), findsOneWidget);
      expect(find.text('Official Website'), findsOneWidget);

      // Call button in Details screen
      final detailsCall = find.byKey(const Key('details_call_button'));
      expect(detailsCall, findsOneWidget);
      await tester.tap(detailsCall);
      await tester.pumpAndSettle();
      expect(detailsCallId, equals(contractorWithFlags.id));
    });
  });
}
