import 'dart:typed_data';
import 'package:renovation_mobile/screens/studio_screen.dart';
import 'package:renovation_mobile/services/photo_picker_service.dart';
import 'package:renovation_mobile/services/render_api_client.dart';
import 'package:renovation_mobile/services/voice_input_service.dart';
import 'package:renovation_mobile/widgets/before_after_slider.dart';
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
import 'package:renovation_mobile/screens/call_screen.dart';
import 'package:renovation_mobile/services/audio_player_service.dart';
import 'package:renovation_mobile/services/call_api_client.dart';

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

class FakeCallApiClient implements CallApiClient {
  @override
  final String baseUrl;

  CallRequest? lastRequest;
  int startCallCount = 0;
  int getStatusCount = 0;
  int stopCallCount = 0;
  final List<CallStatusResponse> statusSequence;

  FakeCallApiClient({
    this.baseUrl = 'http://test-server:8000',
    this.statusSequence = const [],
  });

  @override
  Future<String> startCall(CallRequest request) async {
    startCallCount++;
    lastRequest = request;
    return 'fake-call-001';
  }

  @override
  Future<CallStatusResponse> getCallStatus(String callId, {int after = 0}) async {
    final idx = getStatusCount < statusSequence.length
        ? getStatusCount
        : (statusSequence.isNotEmpty ? statusSequence.length - 1 : 0);
    getStatusCount++;
    if (statusSequence.isEmpty) {
      return CallStatusResponse(
        status: 'queued',
        phase: 'negotiating',
        turns: [],
        warnings: [],
      );
    }
    final resp = statusSequence[idx];
    final filteredTurns = resp.turns.where((t) => t.index >= after).toList();
    return CallStatusResponse(
      status: resp.status,
      phase: resp.phase,
      simulated: resp.simulated,
      isReplay: resp.isReplay,
      turns: filteredTurns,
      outcome: resp.outcome,
      match: resp.match,
      booking: resp.booking,
      warnings: resp.warnings,
      error: resp.error,
    );
  }

  @override
  Future<CallStatusResponse> stopCall(String callId) async {
    stopCallCount++;
    return CallStatusResponse(
      status: 'stopped',
      phase: 'done',
      turns: [],
      warnings: [],
    );
  }

  @override
  String resolveAudioUrl(String audioUrl) {
    if (audioUrl.startsWith('http')) return audioUrl;
    return '$baseUrl/$audioUrl';
  }
}

class FakeCallAudioPlayer implements CallAudioPlayer {
  final List<String> playedUrls = [];
  final bool shouldThrow;
  final Duration playDuration;
  final void Function(String url)? onPlayStarted;
  int stopCount = 0;
  int disposeCount = 0;

  FakeCallAudioPlayer({
    this.shouldThrow = false,
    this.playDuration = Duration.zero,
    this.onPlayStarted,
  });

  @override
  Future<void> playUrl(String url) async {
    onPlayStarted?.call(url);
    if (shouldThrow) {
      throw Exception('Audio player simulated failure');
    }
    if (playDuration > Duration.zero) {
      await Future.delayed(playDuration);
    }
    playedUrls.add(url);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
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




final defaultRenderResult = RenderResult(
  beforeUrl: '/static/renders/before_fake.jpg',
  afterUrl: '/static/renders/after_fake.jpg',
  renovationPrompt: 'Keep the window and room layout. Paint the walls and ceiling warm off-white and lay oak parquet for a Japandi bedroom.',
  voiceConfirmation: 'I have redesigned your bedroom with warm off-white walls and oak parquet.',
  audioUrl: '/static/audio/confirmation_fake.mp3',
  modelUsed: 'Nano Banana v1',
  latencyMs: 1850,
  room: RoomInfo(type: 'bedroom', surfaceM2: 14, confidence: 'high'),
  style: 'Japandi',
  workItems: [
    WorkItem(trade: 'painting', description: 'Warm off-white walls and ceiling', quantity: 45, unit: 'm2'),
    WorkItem(trade: 'flooring', description: 'Oak parquet flooring', quantity: 14, unit: 'm2'),
  ],
);

class FakeRenderApiClient implements RenderApiClient {
  @override
  final String baseUrl;
  int createRenderCount = 0;
  int getStatusCount = 0;
  RenderRequest? lastRequest;
  bool shouldFailCreate;
  bool shouldFailPoll;
  final List<RenderStatusResponse> statusSequence;
  RenderResult? resultToReturn;

  FakeRenderApiClient({
    this.baseUrl = 'http://test-server:8000',
    this.shouldFailCreate = false,
    this.shouldFailPoll = false,
    this.statusSequence = const [],
    this.resultToReturn,
  });

  @override
  Future<String> createRender(RenderRequest request) async {
    createRenderCount++;
    lastRequest = request;
    if (shouldFailCreate) {
      throw Exception('Create render failed: Server error');
    }
    return 'fake-render-001';
  }

  @override
  Future<RenderStatusResponse> getRenderStatus(String renderId) async {
    getStatusCount++;
    if (shouldFailPoll) {
      return RenderStatusResponse(
        status: 'failed',
        phase: 'rendering',
        error: 'Diffusion model error',
      );
    }
    if (statusSequence.isNotEmpty) {
      final idx = (getStatusCount - 1) < statusSequence.length
          ? (getStatusCount - 1)
          : statusSequence.length - 1;
      return statusSequence[idx];
    }
    return RenderStatusResponse(
      status: 'completed',
      phase: 'done',
      isReplay: true,
      result: resultToReturn ?? defaultRenderResult,
    );
  }

  @override
  String resolveUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$baseUrl$path';
  }
}

class FakeVoiceInputService extends VoiceInputService {
  final bool available;
  final String? simulatedSpeechResult;
  int startListeningCount = 0;
  int stopListeningCount = 0;

  FakeVoiceInputService({
    this.available = true,
    this.simulatedSpeechResult,
  });

  @override
  bool get isAvailable => available;

  @override
  Future<bool> initialize() async => available;

  @override
  Future<bool> startListening({
    required void Function(String text) onResult,
    void Function(String finalTranscript)? onDone,
  }) async {
    startListeningCount++;
    if (!available) return false;
    if (simulatedSpeechResult != null) {
      onResult(simulatedSpeechResult!);
      onDone?.call(simulatedSpeechResult!);
    }
    return true;
  }

  @override
  Future<void> stopListening({
    void Function(String transcript)? onStopped,
  }) async {
    stopListeningCount++;
    if (simulatedSpeechResult != null) {
      onStopped?.call(simulatedSpeechResult!);
    }
  }
}

class FakePhotoPickerService extends PhotoPickerService {
  final PickedRoomPhoto? photoToReturn;
  final bool shouldThrow;

  FakePhotoPickerService({
    this.photoToReturn,
    this.shouldThrow = false,
  });

  @override
  Future<PickedRoomPhoto> loadSampleRoom() async {
    if (shouldThrow) throw Exception('Load sample room failed');
    if (photoToReturn != null) return photoToReturn!;
    return PickedRoomPhoto(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      mimeType: 'image/jpeg',
      label: 'Sample Japandi Room',
    );
  }

  @override
  Future<PickedRoomPhoto?> pickFromGallery() async {
    return photoToReturn ??
        PickedRoomPhoto(
          bytes: Uint8List.fromList([5, 6, 7, 8]),
          mimeType: 'image/png',
          label: 'Gallery Photo',
        );
  }

  @override
  Future<PickedRoomPhoto?> pickFromCamera() async {
    return photoToReturn ??
        PickedRoomPhoto(
          bytes: Uint8List.fromList([9, 10, 11, 12]),
          mimeType: 'image/jpeg',
          label: 'Camera Photo',
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
      await tester.ensureVisible(startButton);
      await tester.pumpAndSettle();
      await tester.tap(startButton);
      await tester.pumpAndSettle();

      // Lands on StudioScreen
      expect(find.byKey(const Key('skip_design_button')), findsOneWidget);

      // Tap skip_design_button to advance to QuizScreen
      final skipButton = find.byKey(const Key('skip_design_button'));
      await tester.ensureVisible(skipButton);
      await tester.pumpAndSettle();
      await tester.tap(skipButton);
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

    testWidgets(
      '6. job_id reaches CallScreen from ResearchScreen -> ResultsScreen -> tapping Call, and prefilled email/address + label are shown',
      (tester) async {
        final fakeResearch = FakeResearchApiClient(result: demoResult);
        final fakeCallApi = FakeCallApiClient(
          statusSequence: [
            CallStatusResponse(
              status: 'queued',
              phase: 'negotiating',
              turns: [],
              warnings: [],
            ),
          ],
        );
        final fakeAudio = FakeCallAudioPlayer();

        await tester.pumpWidget(
          MaterialApp(
            home: ResearchScreen(
              project: demoProject,
              answers: QuizAnswers(
                budget: '7000',
                scope: 'partial',
                timeline: 'flexible',
                priority: 'balanced',
                trustRequirements: ['insurance'],
              ),
              apiClient: fakeResearch,
              callApiClient: fakeCallApi,
              audioPlayer: fakeAudio,
            ),
          ),
        );

        // Advance through ResearchScreen into ResultsScreen
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byType(ResultsScreen), findsOneWidget);

        // Tap Call on contractor 1 (onCallPressed is null, so it navigates to CallScreen)
        final callBtn = find.byKey(Key('call_button_${demoResult.contractors[0].id}'));
        expect(callBtn, findsOneWidget);
        await tester.ensureVisible(callBtn);
        await tester.tap(callBtn);
        await tester.pumpAndSettle();

        expect(find.byType(CallScreen), findsOneWidget);

        // Verify permanent label
        expect(
          find.text('Simulated call: AI customer agent and AI renovator agent'),
          findsOneWidget,
        );

        // Verify prefilled email and address
        final emailFinder = find.byKey(const Key('call_email_field'));
        final addressFinder = find.byKey(const Key('call_address_field'));
        expect(emailFinder, findsOneWidget);
        expect(addressFinder, findsOneWidget);
        expect(find.text('demo.customer@example.com'), findsOneWidget);
        expect(find.text('12 Rue de Rivoli, 75004 Paris, France'), findsOneWidget);

        // Tap Start Call button
        final startBtn = find.byKey(const Key('start_call_button'));
        expect(startBtn, findsOneWidget);
        await tester.tap(startBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(fakeCallApi.startCallCount, equals(1));
        expect(fakeCallApi.lastRequest?.jobId, equals('fake-job-001'));
        expect(fakeCallApi.lastRequest?.contractorId, equals(demoResult.contractors[0].id));
        expect(fakeCallApi.lastRequest?.meeting.customerEmail, equals('demo.customer@example.com'));
      },
    );

    testWidgets(
      '7. Turns play strictly in order one at a time, transcript appears when audio starts, completion shows summary without max_price/floor_price',
      (tester) async {
        final turns = [
          CallTurn(
            index: 0,
            speaker: 'customer_agent',
            text: 'Hello renovator, we want Japandi style.',
            audioUrl: 'audio/0.wav',
          ),
          CallTurn(
            index: 1,
            speaker: 'renovator_agent',
            text: 'Hello customer, our estimate is 9200 EUR.',
            audioUrl: 'audio/1.wav',
          ),
        ];

        final outcome = CallOutcome(
          endReason: 'agreement',
          openingPrice: 9200,
          finalPrice: 7650,
          savings: 1550,
          currency: 'EUR',
          labourIncluded: true,
          materialsIncluded: true,
          taxIncluded: true,
          scopeConfirmed: true,
          agreedSlot: '2026-11-02T14:00:00+01:00',
          notes: 'Agreed on Japandi finishes',
        );

        final match = CallMatch(
          match: true,
          reasons: ['Within budget range', 'Valid decennale insurance'],
        );

        final booking = CallBooking(
          status: 'created',
          startsAt: '2026-11-02T14:00:00+01:00',
          location: '12 Rue de Rivoli, Paris',
          eventUrl: 'https://calendar.google.com/calendar/event?eid=demo123',
          warnings: ['Simulated invite only'],
        );

        final fakeCallApi = FakeCallApiClient(
          statusSequence: [
            CallStatusResponse(
              status: 'running',
              phase: 'negotiating',
              turns: turns,
              warnings: [],
            ),
            CallStatusResponse(
              status: 'completed',
              phase: 'done',
              turns: turns,
              outcome: outcome,
              match: match,
              booking: booking,
              warnings: [],
            ),
          ],
        );

        final fakeAudio = FakeCallAudioPlayer(
          playDuration: const Duration(milliseconds: 200),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: CallScreen(
              jobId: 'job-999',
              contractor: demoResult.contractors[0],
              callApiClient: fakeCallApi,
              audioPlayer: fakeAudio,
              pollInterval: const Duration(milliseconds: 50),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Start Call
        await tester.tap(find.byKey(const Key('start_call_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // When Turn 0 starts playing (playDuration = 200ms)
        expect(find.text('Hello renovator, we want Japandi style.'), findsOneWidget);
        expect(find.text('Hello customer, our estimate is 9200 EUR.'), findsNothing);

        // Advance to complete Turn 0 and start Turn 1
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Hello customer, our estimate is 9200 EUR.'), findsOneWidget);

        // Finish Turn 1 playback
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Verify summary card
        expect(find.byKey(const Key('call_summary_card')), findsOneWidget);
        expect(find.textContaining('9200 EUR -> 7650 EUR (Saved 1550 EUR)'), findsOneWidget);
        expect(find.text('Match'), findsOneWidget);
        expect(find.text('• Within budget range'), findsOneWidget);
        expect(find.text('• Valid decennale insurance'), findsOneWidget);
        expect(find.byKey(const Key('booking_event_link')), findsOneWidget);
        expect(find.text('https://calendar.google.com/calendar/event?eid=demo123'), findsOneWidget);

        // Strict guardrail check
        expect(find.textContaining('max_price'), findsNothing);
        expect(find.textContaining('floor_price'), findsNothing);
      },
    );

    testWidgets(
      '8. Fallback works without audio (audio_url null or audio player error still displays transcript turns and completes)',
      (tester) async {
        final turns = [
          CallTurn(
            index: 0,
            speaker: 'customer_agent',
            text: 'Turn 1 with null audio',
            audioUrl: null,
          ),
          CallTurn(
            index: 1,
            speaker: 'renovator_agent',
            text: 'Turn 2 with failing audio player',
            audioUrl: 'audio/error.wav',
          ),
        ];

        final outcome = CallOutcome(
          endReason: 'agreement',
          openingPrice: 8000,
          finalPrice: 7000,
          savings: 1000,
          currency: 'EUR',
        );

        final fakeCallApi = FakeCallApiClient(
          statusSequence: [
            CallStatusResponse(
              status: 'completed',
              phase: 'done',
              turns: turns,
              outcome: outcome,
              match: CallMatch(match: true, reasons: ['Good fit']),
              booking: CallBooking(status: 'link_only', warnings: []),
              warnings: ['Replay fallback'],
              isReplay: true,
            ),
          ],
        );

        final fakeAudio = FakeCallAudioPlayer(shouldThrow: true);

        await tester.pumpWidget(
          MaterialApp(
            home: CallScreen(
              jobId: 'job-fallback-123',
              contractor: demoResult.contractors[0],
              callApiClient: fakeCallApi,
              audioPlayer: fakeAudio,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Start call
        await tester.tap(find.byKey(const Key('start_call_button')));
        await tester.pump();
        await tester.pumpAndSettle();

        // Both turns should be visible
        expect(find.text('Turn 1 with null audio'), findsOneWidget);
        expect(find.text('Turn 2 with failing audio player'), findsOneWidget);

        // Replay badge visible
        expect(find.byKey(const Key('replay_badge')), findsOneWidget);

        // Completion summary card visible
        expect(find.byKey(const Key('call_summary_card')), findsOneWidget);
        expect(find.textContaining('8000 EUR -> 7000 EUR (Saved 1000 EUR)'), findsOneWidget);
      },
    );
  });

  
  
  
  
  group('AuraSpace Studio Flow Tests', () {
    testWidgets(
      '1. Studio loads sample room, fills "Use sample brief", taps "Renovate", displays phase progress (planning -> rendering -> narrating -> done), and renders BeforeAfterSlider (35%), Replay badge, latency chip, and spoken confirmation',
      (WidgetTester tester) async {
        final fakeRenderApi = FakeRenderApiClient(
          statusSequence: [
            RenderStatusResponse(status: 'running', phase: 'planning'),
            RenderStatusResponse(status: 'running', phase: 'rendering'),
            RenderStatusResponse(status: 'running', phase: 'narrating'),
            RenderStatusResponse(
              status: 'completed',
              phase: 'done',
              isReplay: true,
              result: defaultRenderResult,
            ),
          ],
        );
        final fakePhotoPicker = FakePhotoPickerService();
        final fakeAudio = FakeCallAudioPlayer();

        await tester.pumpWidget(
          MaterialApp(
            home: StudioScreen(
              city: 'Paris',
              country: 'France',
              renderApiClient: fakeRenderApi,
              photoPickerService: fakePhotoPicker,
              audioPlayerFactory: () => fakeAudio,
              pollInterval: const Duration(milliseconds: 50),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Load sample room
        final loadSampleBtn = find.byKey(const Key('use_sample_room_button'));
        await tester.ensureVisible(loadSampleBtn);
        await tester.tap(loadSampleBtn);
        await tester.pumpAndSettle();
        expect(find.text('Source: Sample Japandi Room'), findsOneWidget);

        // 2. Fill sample brief
        final sampleBriefBtn = find.byKey(const Key('use_sample_brief_button'));
        await tester.ensureVisible(sampleBriefBtn);
        await tester.tap(sampleBriefBtn);
        await tester.pumpAndSettle();
        expect(find.text(kSampleBrief), findsOneWidget);

        // 3. Tap Renovate
        final renovateBtn = find.byKey(const Key('renovate_button'));
        await tester.ensureVisible(renovateBtn);
        await tester.tap(renovateBtn);
        await tester.pump();

        // Planning phase
        expect(find.byKey(const Key('render_phase_indicator')), findsOneWidget);
        expect(find.text('Planning renovation & extracting scope...'), findsOneWidget);

        // Rendering phase
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('Generating Nano Banana after render...'), findsOneWidget);

        // Narrating phase
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('Synthesizing voice confirmation...'), findsOneWidget);

        // Done / Completed
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();

        // Verify BeforeAfterSlider
        expect(find.byType(BeforeAfterSlider), findsOneWidget);
        expect(find.byKey(const Key('before_after_slider')), findsOneWidget);
        expect(find.text('Before'), findsOneWidget);
        expect(find.text('After'), findsOneWidget);

        // Drag handle to 35%
        final dragHandle = find.byKey(const Key('slider_drag_handle'));
        expect(dragHandle, findsOneWidget);
        await tester.ensureVisible(dragHandle);
        await tester.drag(dragHandle, const Offset(-40, 0));
        await tester.pumpAndSettle();

        // Verify Replay badge (is_replay: true)
        expect(find.byKey(const Key('render_replay_badge')), findsOneWidget);
        expect(find.text('Replay'), findsOneWidget);

        // Verify latency chip (1850ms -> 1.9s)
        expect(find.byKey(const Key('render_latency_chip')), findsOneWidget);
        expect(find.text('1.9s'), findsOneWidget);

        // Verify spoken confirmation text
        expect(find.byKey(const Key('voice_confirmation_text')), findsOneWidget);
        expect(
          find.text('"${defaultRenderResult.voiceConfirmation}"'),
          findsOneWidget,
        );

        // Verify audio played via resolved URL
        expect(fakeAudio.playedUrls, contains('http://test-server:8000/static/audio/confirmation_fake.mp3'));
      },
    );

    testWidgets(
      '2. Tapping "Find renovators for this design" passes Studio\'s Project to QuizScreen and submits that project to POST /research',
      (WidgetTester tester) async {
        final fakeRenderApi = FakeRenderApiClient(resultToReturn: defaultRenderResult);
        final fakeResearchApi = FakeResearchApiClient(result: demoResult);
        final fakePhotoPicker = FakePhotoPickerService();

        await tester.pumpWidget(
          MaterialApp(
            home: StudioScreen(
              city: 'Marseille',
              country: 'France',
              quizConfig: quizConfig,
              apiClient: fakeResearchApi,
              renderApiClient: fakeRenderApi,
              photoPickerService: fakePhotoPicker,
              pollInterval: const Duration(milliseconds: 50),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Load room and brief, then renovate
        final loadSampleBtn = find.byKey(const Key('use_sample_room_button'));
        await tester.ensureVisible(loadSampleBtn);
        await tester.tap(loadSampleBtn);
        await tester.pumpAndSettle();

        final sampleBriefBtn = find.byKey(const Key('use_sample_brief_button'));
        await tester.ensureVisible(sampleBriefBtn);
        await tester.tap(sampleBriefBtn);
        await tester.pumpAndSettle();

        final renovateBtn = find.byKey(const Key('renovate_button'));
        await tester.ensureVisible(renovateBtn);
        await tester.tap(renovateBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();

        // Primary CTA: Find renovators for this design
        final findRenovatorsBtn = find.byKey(const Key('find_renovators_button'));
        expect(findRenovatorsBtn, findsOneWidget);
        await tester.ensureVisible(findRenovatorsBtn);
        await tester.tap(findRenovatorsBtn);
        await tester.pumpAndSettle();

        // Lands on QuizScreen
        expect(find.text('Question 1 of 5'), findsOneWidget);

        // Step through all 5 questions
        await tester.tap(find.byKey(const Key('option_5k_15k')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('next_quiz_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('option_partial')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('next_quiz_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('option_one_to_three_months')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('next_quiz_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('option_balanced')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('next_quiz_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('option_licensed_insured')));
        await tester.pumpAndSettle();
        final submitBtn = find.byKey(const Key('submit_quiz_button'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify POST /research was called with Studio project
        expect(fakeResearchApi.startCallCount, 1);
        final submittedProject = fakeResearchApi.lastProject!;
        expect(submittedProject.client.city, 'Marseille');
        expect(submittedProject.room.type, 'bedroom');
        expect(submittedProject.room.surfaceM2, 14);
        expect(submittedProject.style, 'Japandi');
        expect(submittedProject.renderUrls, contains('http://test-server:8000/static/renders/after_fake.jpg'));

        // Verify ResultsScreen shows renovation design preview
        expect(find.byKey(const Key('results_render_preview')), findsOneWidget);
        expect(find.text('Your Renovation Design'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Tapping "Skip design and use sample project" proceeds to QuizScreen with sample project',
      (WidgetTester tester) async {
        final fakeResearchApi = FakeResearchApiClient(result: demoResult);

        await tester.pumpWidget(
          MaterialApp(
            home: StudioScreen(
              city: 'Bordeaux',
              initialProject: demoProject,
              quizConfig: quizConfig,
              apiClient: fakeResearchApi,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Skip design button
        final skipBtn = find.byKey(const Key('skip_design_button'));
        expect(skipBtn, findsOneWidget);
        await tester.ensureVisible(skipBtn);
        await tester.tap(skipBtn);
        await tester.pumpAndSettle();

        // Lands on QuizScreen
        expect(find.text('Question 1 of 5'), findsOneWidget);
        expect(
          find.text('What is your total budget, including labour, materials and tax?'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '4. When mic is unavailable, tapping mic shows Key(\'mic_unavailable_message\') and does not insert fake transcript',
      (WidgetTester tester) async {
        final fakeVoice = FakeVoiceInputService(available: false);

        await tester.pumpWidget(
          MaterialApp(
            home: StudioScreen(
              voiceInputService: fakeVoice,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify mic unavailable warning is not visible initially
        expect(find.byKey(const Key('mic_unavailable_message')), findsNothing);

        // Tap mic dictation button
        final micBtn = find.byKey(const Key('voice_dictation_button'));
        expect(micBtn, findsOneWidget);
        await tester.ensureVisible(micBtn);
        await tester.tap(micBtn);
        await tester.pumpAndSettle();

        // Warning message should now appear
        expect(find.byKey(const Key('mic_unavailable_message')), findsOneWidget);
        expect(
          find.text(
            'Microphone dictation is unavailable on this device or browser. Please type your brief or use the sample brief.',
          ),
          findsOneWidget,
        );

        // Verify brief field remains empty and no fake transcript was inserted
        final briefField = tester.widget<TextField>(find.byKey(const Key('brief_input_field')));
        expect(briefField.controller?.text, isEmpty);
      },
    );

    testWidgets(
      '5. When POST /renders or GET /renders/{id} fails, StudioScreen shows error banner and Retry button',
      (WidgetTester tester) async {
        final fakeRenderApi = FakeRenderApiClient(shouldFailCreate: true);
        final fakePhotoPicker = FakePhotoPickerService();

        await tester.pumpWidget(
          MaterialApp(
            home: StudioScreen(
              renderApiClient: fakeRenderApi,
              photoPickerService: fakePhotoPicker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Prepare inputs
        final loadSampleBtn = find.byKey(const Key('use_sample_room_button'));
        await tester.ensureVisible(loadSampleBtn);
        await tester.tap(loadSampleBtn);
        await tester.pumpAndSettle();

        final sampleBriefBtn = find.byKey(const Key('use_sample_brief_button'));
        await tester.ensureVisible(sampleBriefBtn);
        await tester.tap(sampleBriefBtn);
        await tester.pumpAndSettle();

        // Tap Renovate -> triggers failure
        final renovateBtn = find.byKey(const Key('renovate_button'));
        await tester.ensureVisible(renovateBtn);
        await tester.tap(renovateBtn);
        await tester.pumpAndSettle();

        // Verify error banner and retry button
        expect(find.byKey(const Key('render_error_banner')), findsOneWidget);
        expect(find.text('Renovation render error'), findsOneWidget);
        expect(find.byKey(const Key('retry_render_button')), findsOneWidget);

        // Now fix failure and test Retry
        fakeRenderApi.shouldFailCreate = false;
        final retryBtn = find.byKey(const Key('retry_render_button'));
        await tester.ensureVisible(retryBtn);
        await tester.tap(retryBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();

        // Error banner should be gone and completion shown
        expect(find.byKey(const Key('render_error_banner')), findsNothing);
        expect(find.byType(BeforeAfterSlider), findsOneWidget);
      },
    );

    testWidgets(
      '6. BeforeAfterSlider renders split before/after with custom initial percent (35%)',
      (WidgetTester tester) async {
        double currentPercent = 0.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BeforeAfterSlider(
                beforeBytes: Uint8List.fromList([1, 2, 3]),
                afterImageUrl: 'http://test-server:8000/after.jpg',
                initialPercent: 35.0,
                onPositionChanged: (p) => currentPercent = p,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('before_after_slider')), findsOneWidget);
        expect(find.text('Before'), findsOneWidget);
        expect(find.text('After'), findsOneWidget);

        final handle = find.byKey(const Key('slider_drag_handle'));
        expect(handle, findsOneWidget);
        await tester.drag(handle, const Offset(50, 0));
        await tester.pumpAndSettle();
        expect(currentPercent, greaterThan(35.0));
      },
    );
  });


  group('Full End-to-End Stage Script Integration Test', () {
    testWidgets(
      'Full Stage Script: StartScreen (Paris) -> StudioScreen (sample room, sample brief, Renovate, slider, Find renovators) -> QuizScreen (Best value overall) -> ResearchScreen -> ResultsScreen (Atelier Kanso + banner) -> CallScreen (9200 to 8200 EUR, Match, booking link)',
      (WidgetTester tester) async {
        final fakeRenderApi = FakeRenderApiClient(
          resultToReturn: defaultRenderResult,
        );
        final fakeResearchApi = FakeResearchApiClient(result: demoResult);
        final fakePhotoPicker = FakePhotoPickerService();
        final fakeAudio = FakeCallAudioPlayer();

        final callTurns = [
          CallTurn(
            index: 0,
            speaker: 'customer_agent',
            text: 'Hello, I am an AI assistant calling for a client regarding painting and oak flooring for a 14 m2 Paris bedroom. Can you help?',
            audioUrl: 'audio/0.wav',
          ),
          CallTurn(
            index: 1,
            speaker: 'renovator_agent',
            text: 'Hello! We handle painting and flooring. Our non-binding estimate is 9200 EUR, including labour, materials, and VAT. How does that sound?',
            audioUrl: 'audio/1.wav',
          ),
          CallTurn(
            index: 2,
            speaker: 'customer_agent',
            text: 'Could you do 7100 EUR? The 14 m2 footprint allows combining crews in one 5-day slot, with flexible start timing.',
            audioUrl: 'audio/2.wav',
          ),
          CallTurn(
            index: 3,
            speaker: 'renovator_agent',
            text: '7100 EUR is too low. With your flexible schedule, the best I can do is 8200 EUR, including labour, materials, and VAT.',
            audioUrl: 'audio/3.wav',
          ),
          CallTurn(
            index: 4,
            speaker: 'customer_agent',
            text: '8200 EUR works non-bindingly. Does that include acoustic underlayment? Also, are you available for a site visit on 2026-11-02T10:00:00+01:00?',
            audioUrl: 'audio/4.wav',
          ),
          CallTurn(
            index: 5,
            speaker: 'renovator_agent',
            text: 'Yes, underlayment is included. I cannot do 10:00, but can we meet on 2026-11-02 at 14:00?',
            audioUrl: 'audio/5.wav',
          ),
          CallTurn(
            index: 6,
            speaker: 'customer_agent',
            text: "Perfect, 2026-11-02T14:00:00+01:00 is confirmed. Please send your attestation d'assurance décennale before the visit. Thank you, goodbye!",
            audioUrl: 'audio/6.wav',
          ),
        ];

        final callOutcome = CallOutcome(
          endReason: 'agreement',
          openingPrice: 9200,
          finalPrice: 8200,
          savings: 1000,
          currency: 'EUR',
          labourIncluded: true,
          materialsIncluded: true,
          taxIncluded: true,
          scopeConfirmed: true,
          agreedSlot: '2026-11-02T14:00:00+01:00',
          notes: 'Scope includes painting, oak flooring, and acoustic underlayment for a 14 m2 Paris bedroom.',
        );

        final callMatch = CallMatch(
          match: true,
          reasons: ['Within budget range', 'Valid decennale insurance'],
        );

        final callBooking = CallBooking(
          status: 'created',
          startsAt: '2026-11-02T14:00:00+01:00',
          location: '12 Rue de Rivoli, Paris',
          eventUrl: 'https://calendar.google.com/calendar/event?eid=demo123',
          warnings: ['Simulated invite only'],
        );

        final fakeCallApi = FakeCallApiClient(
          statusSequence: [
            CallStatusResponse(
              status: 'completed',
              phase: 'done',
              isReplay: true,
              turns: callTurns,
              outcome: callOutcome,
              match: callMatch,
              booking: callBooking,
              warnings: [],
            ),
          ],
        );

        // 1. Launch RenovationApp
        await tester.pumpWidget(
          RenovationApp(
            initialProject: demoProject,
            initialQuizConfig: quizConfig,
            apiClient: fakeResearchApi,
            renderApiClient: fakeRenderApi,
            callApiClient: fakeCallApi,
            photoPickerService: fakePhotoPicker,
            audioPlayer: fakeAudio,
          ),
        );
        await tester.pumpAndSettle();

        // Verify StartScreen with Paris
        expect(find.text('Project Summary'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Paris'), findsOneWidget);

        // Tap "Open Design Studio"
        final startBtn = find.byKey(const Key('start_quiz_button'));
        await tester.ensureVisible(startBtn);
        await tester.tap(startBtn);
        await tester.pumpAndSettle();

        // 2. StudioScreen
        expect(find.byKey(const Key('use_sample_room_button')), findsOneWidget);

        // Use sample room
        final sampleRoomBtn = find.byKey(const Key('use_sample_room_button'));
        await tester.ensureVisible(sampleRoomBtn);
        await tester.tap(sampleRoomBtn);
        await tester.pumpAndSettle();

        // Use sample brief
        final sampleBriefBtn = find.byKey(const Key('use_sample_brief_button'));
        await tester.ensureVisible(sampleBriefBtn);
        await tester.tap(sampleBriefBtn);
        await tester.pumpAndSettle();

        // Tap Renovate
        final renovateBtn = find.byKey(const Key('renovate_button'));
        await tester.ensureVisible(renovateBtn);
        await tester.tap(renovateBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();

        // Drag slider
        final sliderHandle = find.byKey(const Key('slider_drag_handle'));
        expect(sliderHandle, findsOneWidget);
        await tester.ensureVisible(sliderHandle);
        await tester.drag(sliderHandle, const Offset(-30, 0));
        await tester.pumpAndSettle();

        // Find renovators for this design
        final findRenovatorsBtn = find.byKey(const Key('find_renovators_button'));
        expect(findRenovatorsBtn, findsOneWidget);
        await tester.ensureVisible(findRenovatorsBtn);
        await tester.tap(findRenovatorsBtn);
        await tester.pumpAndSettle();

        // 3. QuizScreen
        expect(find.text('Question 1 of 5'), findsOneWidget);

        // Q1: Budget
        await tester.tap(find.byKey(const Key('option_5k_15k')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('next_quiz_button')));
        await tester.pumpAndSettle();

        // Q2: Scope
        await tester.tap(find.byKey(const Key('option_partial')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('next_quiz_button')));
        await tester.pumpAndSettle();

        // Q3: Timeline
        await tester.tap(find.byKey(const Key('option_one_to_three_months')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('next_quiz_button')));
        await tester.pumpAndSettle();

        // Q4: Priority -> 'balanced' ("Best value overall")
        expect(find.text('Best value overall'), findsOneWidget);
        await tester.tap(find.byKey(const Key('option_balanced')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('next_quiz_button')));
        await tester.pumpAndSettle();

        // Q5: Trust requirements
        await tester.tap(find.byKey(const Key('option_licensed_insured')));
        await tester.pumpAndSettle();

        final submitQuizBtn = find.byKey(const Key('submit_quiz_button'));
        await tester.ensureVisible(submitQuizBtn);
        await tester.tap(submitQuizBtn);
        await tester.pump();
        await tester.pumpAndSettle();

        // 4. ResearchScreen automatically advances to ResultsScreen
        expect(find.byType(ResultsScreen), findsOneWidget);

        // Verify ResultsScreen shows render preview banner and Atelier Kanso (#1)
        expect(find.byKey(const Key('results_render_preview')), findsOneWidget);
        expect(find.text('Your Renovation Design'), findsOneWidget);
        expect(find.text('Atelier Kanso Renovations (Fictional Demo Co.)'), findsOneWidget);

        // 5. Tap Call on Atelier Kanso (#1)
        final callBtn = find.byKey(Key('call_button_${demoResult.contractors[0].id}'));
        expect(callBtn, findsOneWidget);
        await tester.ensureVisible(callBtn);
        await tester.tap(callBtn);
        await tester.pumpAndSettle();

        // 6. CallScreen
        expect(find.byType(CallScreen), findsOneWidget);

        // Tap Start Call
        final startCallBtn = find.byKey(const Key('start_call_button'));
        expect(startCallBtn, findsOneWidget);
        await tester.tap(startCallBtn);
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify call outcome: 9200 to 8200 EUR, Match, and booking link
        final summaryCard = find.byKey(const Key('call_summary_card'));
        await tester.scrollUntilVisible(summaryCard, 100);
        expect(summaryCard, findsOneWidget);
        expect(find.textContaining('9200 EUR -> 8200 EUR (Saved 1000 EUR)'), findsOneWidget);
        expect(find.text('Match'), findsOneWidget);
        expect(find.byKey(const Key('booking_event_link')), findsOneWidget);
        expect(find.text('https://calendar.google.com/calendar/event?eid=demo123'), findsOneWidget);
      },
    );
  });
}
