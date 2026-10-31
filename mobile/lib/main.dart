import 'package:flutter/material.dart';
import 'models/models.dart';
import 'screens/start_screen.dart';
import 'services/api_client.dart';
import 'services/audio_player_service.dart';
import 'services/call_handler.dart';
import 'services/photo_picker_service.dart';
import 'services/render_api_client.dart';
import 'services/voice_input_service.dart';

void main() {
  runApp(const RenovationApp());
}

class RenovationApp extends StatelessWidget {
  final Project? initialProject;
  final QuizConfig? initialQuizConfig;
  final ResearchApiClient? apiClient;
  final RenderApiClient? renderApiClient;
  final PhotoPickerService? photoPickerService;
  final VoiceInputService? voiceInputService;
  final CallAudioPlayer Function()? audioPlayerFactory;
  final OnCallPressedCallback? onCallPressed;

  const RenovationApp({
    super.key,
    this.initialProject,
    this.initialQuizConfig,
    this.apiClient,
    this.renderApiClient,
    this.photoPickerService,
    this.voiceInputService,
    this.audioPlayerFactory,
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
      home: StartScreen(
        initialProject: initialProject,
        initialQuizConfig: initialQuizConfig,
        apiClient: apiClient,
        renderApiClient: renderApiClient,
        photoPickerService: photoPickerService,
        voiceInputService: voiceInputService,
        audioPlayerFactory: audioPlayerFactory,
        onCallPressed: onCallPressed,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
