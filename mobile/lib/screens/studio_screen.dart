import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
import '../widgets/before_after_slider.dart';
import 'quiz_screen.dart';

const String kSampleBrief =
    'Keep the window and room layout. Paint the walls and ceiling warm off-white and lay oak parquet for a Japandi bedroom.';

class StudioScreen extends StatefulWidget {
  final String city;
  final String country;
  final Project? initialProject;
  final QuizConfig? quizConfig;
  final ResearchApiClient? apiClient;
  final RenderApiClient? renderApiClient;
  final PhotoPickerService? photoPickerService;
  final VoiceInputService? voiceInputService;
  final CallApiClient? callApiClient;
  final CallAudioPlayer Function()? audioPlayerFactory;
  final CallAudioPlayer? audioPlayer;
  final OnCallPressedCallback? onCallPressed;
  final Duration pollInterval;

  const StudioScreen({
    super.key,
    this.city = 'Paris',
    this.country = 'France',
    this.initialProject,
    this.quizConfig,
    this.apiClient,
    this.renderApiClient,
    this.photoPickerService,
    this.voiceInputService,
    this.callApiClient,
    this.audioPlayerFactory,
    this.audioPlayer,
    this.onCallPressed,
    this.pollInterval = const Duration(seconds: 1),
  });

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  late final ResearchApiClient _researchClient;
  late final RenderApiClient _renderClient;
  late final PhotoPickerService _photoPicker;
  late final VoiceInputService _voiceService;
  CallAudioPlayer? _audioPlayer;

  late final TextEditingController _briefController;

  Uint8List? _currentPhotoBytes;
  String _currentMimeType = 'image/jpeg';
  String _currentPhotoLabel = 'Sample Japandi Room';

  bool _isListening = false;
  bool _micUnavailable = false;

  bool _isGenerating = false;
  String? _renderStatus; // 'queued' | 'running' | 'completed' | 'failed'
  String? _renderPhase; // 'planning' | 'rendering' | 'narrating' | 'done'
  String? _errorMessage;
  RenderResult? _renderResult;
  bool _isReplay = false;
  double _sliderPercent = 50.0;

  bool _isMuted = false;
  bool _isPlayingAudio = false;

  Timer? _pollTimer;
  String? _activeRenderId;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _researchClient = widget.apiClient ?? HttpResearchApiClient();
    _renderClient = widget.renderApiClient ?? HttpRenderApiClient();
    _photoPicker = widget.photoPickerService ?? PhotoPickerService();
    _voiceService = widget.voiceInputService ?? VoiceInputService();
    _audioPlayer = widget.audioPlayer ?? widget.audioPlayerFactory?.call() ?? AudioplayersCallAudioPlayer();

    _briefController = TextEditingController();

    _loadSampleRoom();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pollTimer?.cancel();
    _briefController.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadSampleRoom() async {
    try {
      final sample = await _photoPicker.loadSampleRoom();
      if (_isDisposed) return;
      setState(() {
        _currentPhotoBytes = sample.bytes;
        _currentMimeType = sample.mimeType;
        _currentPhotoLabel = sample.label;
      });
    } catch (e) {
      debugPrint('Failed to load sample room photo: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    final photo = await _photoPicker.pickFromGallery();
    if (photo != null && !_isDisposed) {
      setState(() {
        _currentPhotoBytes = photo.bytes;
        _currentMimeType = photo.mimeType;
        _currentPhotoLabel = photo.label;
        _renderResult = null;
        _sliderPercent = 50.0;
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickFromCamera() async {
    final photo = await _photoPicker.pickFromCamera();
    if (photo != null && !_isDisposed) {
      setState(() {
        _currentPhotoBytes = photo.bytes;
        _currentMimeType = photo.mimeType;
        _currentPhotoLabel = photo.label;
        _renderResult = null;
        _sliderPercent = 50.0;
        _errorMessage = null;
      });
    }
  }

  void _fillSampleBrief() {
    setState(() {
      _briefController.text = kSampleBrief;
    });
  }

  Future<void> _toggleVoiceDictation() async {
    if (_isListening) {
      await _voiceService.stopListening(
        onStopped: (transcript) {
          if (!_isDisposed) {
            setState(() {
              _isListening = false;
              if (transcript.trim().isNotEmpty) {
                _briefController.text = transcript.trim();
              }
            });
            if (_briefController.text.trim().isNotEmpty) {
              _startRenovation();
            }
          }
        },
      );
      return;
    }

    final available = await _voiceService.initialize();
    if (!available) {
      if (!_isDisposed) {
        setState(() {
          _micUnavailable = true;
          _isListening = false;
        });
      }
      return;
    }

    setState(() {
      _micUnavailable = false;
      _isListening = true;
    });

    final started = await _voiceService.startListening(
      onResult: (text) {
        if (!_isDisposed && text.trim().isNotEmpty) {
          setState(() {
            _briefController.text = text;
          });
        }
      },
      onDone: (finalText) {
        if (!_isDisposed) {
          setState(() {
            _isListening = false;
            if (finalText.trim().isNotEmpty) {
              _briefController.text = finalText.trim();
            }
          });
          if (_briefController.text.trim().isNotEmpty) {
            _startRenovation();
          }
        }
      },
    );

    if (!started && !_isDisposed) {
      setState(() {
        _micUnavailable = true;
        _isListening = false;
      });
    }
  }

  Future<void> _startRenovation() async {
    if (_currentPhotoBytes == null) return;
    final instruction = _briefController.text.trim();
    if (instruction.isEmpty) return;

    _pollTimer?.cancel();
    setState(() {
      _isGenerating = true;
      _renderStatus = 'queued';
      _renderPhase = 'planning';
      _errorMessage = null;
      _renderResult = null;
    });

    try {
      final req = RenderRequest(
        imageBase64: base64Encode(_currentPhotoBytes!),
        mimeType: _currentMimeType,
        instruction: instruction,
        city: widget.city,
        country: widget.country,
      );

      final renderId = await _renderClient.createRender(req);
      if (_isDisposed) return;
      _activeRenderId = renderId;

      await _pollRenderStatus();
      if (_isDisposed || _renderStatus == 'completed' || _renderStatus == 'failed') {
        return;
      }

      _pollTimer = Timer.periodic(widget.pollInterval, (_) {
        _pollRenderStatus();
      });
    } catch (e) {
      if (_isDisposed) return;
      setState(() {
        _isGenerating = false;
        _renderStatus = 'failed';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _pollRenderStatus() async {
    if (_activeRenderId == null || _isDisposed) return;

    try {
      final statusResp = await _renderClient.getRenderStatus(_activeRenderId!);
      if (_isDisposed) return;

      setState(() {
        _renderStatus = statusResp.status;
        _renderPhase = statusResp.phase;
        _isReplay = statusResp.isReplay;
      });

      if (statusResp.isCompleted && statusResp.result != null) {
        _pollTimer?.cancel();
        setState(() {
          _isGenerating = false;
          _renderResult = statusResp.result;
          _sliderPercent = 35.0; // Reveal 65% of the renovation after render
        });

        // Automatically play voice confirmation if not muted
        if (!_isMuted && statusResp.result!.audioUrl != null) {
          _playAudio(statusResp.result!.audioUrl!);
        }
      } else if (statusResp.isFailed) {
        _pollTimer?.cancel();
        setState(() {
          _isGenerating = false;
          _renderStatus = 'failed';
          _errorMessage = statusResp.error ?? 'Renovation rendering failed.';
        });
      }
    } catch (e) {
      if (_isDisposed) return;
      _pollTimer?.cancel();
      setState(() {
        _isGenerating = false;
        _renderStatus = 'failed';
        _errorMessage = 'Status check failed: $e';
      });
    }
  }

  Future<void> _playAudio(String audioUrl) async {
    if (_audioPlayer == null) return;
    try {
      setState(() => _isPlayingAudio = true);
      final resolved = _renderClient.resolveUrl(audioUrl);
      await _audioPlayer!.playUrl(resolved);
    } catch (e) {
      debugPrint('Voice confirmation audio error: $e');
    } finally {
      if (!_isDisposed) {
        setState(() => _isPlayingAudio = false);
      }
    }
  }

  String _getPhaseDescription(String? phase) {
    switch (phase) {
      case 'planning':
        return 'Planning renovation & extracting scope...';
      case 'rendering':
        return 'Generating Nano Banana after render...';
      case 'narrating':
        return 'Synthesizing voice confirmation...';
      case 'done':
        return 'Finalizing renovation design...';
      default:
        return 'Preparing your renovation...';
    }
  }

  void _onFindRenovatorsPressed() {
    if (_renderResult == null) return;
    final project = _renderResult!.toProject(
      city: widget.city,
      country: widget.country,
      baseUrl: _renderClient.baseUrl,
    );
    final afterUrl = _renderClient.resolveUrl(_renderResult!.afterUrl);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(
          initialProject: project,
          quizConfig: widget.quizConfig,
          afterRenderUrl: afterUrl,
          apiClient: _researchClient,
          callApiClient: widget.callApiClient,
          audioPlayer: widget.audioPlayer,
          onCallPressed: widget.onCallPressed,
        ),
      ),
    );
  }

  Future<void> _onSkipDesignPressed() async {
    try {
      Project project;
      if (widget.initialProject != null) {
        project = widget.initialProject!;
      } else {
        final raw = await rootBundle.loadString('assets/shared/fixtures/demo_project.json');
        final data = jsonDecode(raw) as Map<String, dynamic>;
        project = Project.fromJson(data);
      }
      if (widget.city.trim().isNotEmpty) {
        project = project.copyWith(
          client: project.client.copyWith(city: widget.city.trim()),
        );
      }

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuizScreen(
            initialProject: project,
            quizConfig: widget.quizConfig,
            apiClient: _researchClient,
            callApiClient: widget.callApiClient,
            audioPlayer: widget.audioPlayer,
            onCallPressed: widget.onCallPressed,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Failed to load demo project: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF818CF8), size: 20),
            const SizedBox(width: 8),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                children: [
                  TextSpan(text: 'AuraSpace '),
                  TextSpan(text: 'Studio', style: TextStyle(color: Color(0xFF818CF8))),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('mute_audio_button'),
            tooltip: _isMuted ? 'Unmute voice' : 'Mute voice',
            icon: Icon(
              _isMuted ? Icons.volume_off : Icons.volume_up,
              color: _isMuted ? Colors.grey : const Color(0xFF34D399),
            ),
            onPressed: () {
              setState(() {
                _isMuted = !_isMuted;
                if (_isMuted) {
                  _audioPlayer?.stop();
                  _isPlayingAudio = false;
                }
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Before/After Slider or Room Photo Preview
              BeforeAfterSlider(
                beforeBytes: _currentPhotoBytes,
                afterImageUrl: _renderResult != null
                    ? _renderClient.resolveUrl(_renderResult!.afterUrl)
                    : null,
                initialPercent: _sliderPercent,
                onPositionChanged: (p) => _sliderPercent = p,
                height: 280,
              ),

              const SizedBox(height: 6),
              Text(
                'Source: $_currentPhotoLabel',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),

              const SizedBox(height: 12),

              // Badges row: Replay badge + Latency chip
              if (_renderResult != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      if (_isReplay)
                        Container(
                          key: const Key('render_replay_badge'),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Replay',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (_isReplay) const SizedBox(width: 8),
                      Container(
                        key: const Key('render_latency_chip'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          '${(_renderResult!.latencyMs / 1000).toStringAsFixed(1)}s',
                          style: const TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          _renderResult!.modelUsed.isNotEmpty
                              ? _renderResult!.modelUsed
                              : 'Nano Banana',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Photo Picker Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('use_sample_room_button'),
                      onPressed: _isGenerating ? null : _loadSampleRoom,
                      icon: const Icon(Icons.image, size: 16),
                      label: const Text('Use sample room', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const Key('pick_gallery_button'),
                    onPressed: _isGenerating ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text('Gallery', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const Key('pick_camera_button'),
                    onPressed: _isGenerating ? null : _pickFromCamera,
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('Camera', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Renovation Brief Input Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'RENOVATION BRIEF',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        TextButton(
                          key: const Key('use_sample_brief_button'),
                          onPressed: _isGenerating ? null : _fillSampleBrief,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(50, 24),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Use sample brief',
                            style: TextStyle(
                              color: Color(0xFF818CF8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Brief text field
                    TextField(
                      key: const Key('brief_input_field'),
                      controller: _briefController,
                      maxLength: 1000,
                      maxLines: 3,
                      enabled: !_isGenerating,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            'Describe your renovation brief (e.g., paint walls warm off-white, install oak parquet)...',
                        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                        counterStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF6366F1)),
                        ),
                      ),
                    ),

                    // Voice Dictation Button
                    const SizedBox(height: 4),
                    ElevatedButton.icon(
                      key: const Key('voice_dictation_button'),
                      onPressed: _isGenerating ? null : _toggleVoiceDictation,
                      icon: Icon(
                        _isListening ? Icons.mic_off : Icons.mic,
                        color: _isListening ? Colors.redAccent : Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        _isListening
                            ? 'Stop Voice & Renovate Space'
                            : 'Dictate Renovation (Continuous Mic)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isListening ? const Color(0xFF7F1D1D) : const Color(0xFF334155),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // Mic Unavailable Warning Message
                    if (_micUnavailable)
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: Container(
                          key: const Key('mic_unavailable_message'),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade900.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade600),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.mic_off, color: Colors.amber.shade400, size: 18),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Microphone dictation is unavailable on this device or browser. Please type your brief or use the sample brief.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Primary Renovate Button
                    ElevatedButton.icon(
                      key: const Key('renovate_button'),
                      onPressed: (_isGenerating || _currentPhotoBytes == null)
                          ? null
                          : _startRenovation,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        _isGenerating ? 'Renovating Space...' : 'Renovate',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Phase progress indicator
              if (_isGenerating)
                Container(
                  key: const Key('render_phase_indicator'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6366F1)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getPhaseDescription(_renderPhase),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Phase: ${_renderPhase ?? 'planning'}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Render Error Banner & Retry Button
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Container(
                    key: const Key('render_error_banner'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0x807F1D1D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Renovation render error',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          key: const Key('retry_render_button'),
                          onPressed: _startRenovation,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Completed Render Details Card
              if (_renderResult != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x8034D399)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Spoken Confirmation Card
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconButton(
                            key: const Key('replay_audio_button'),
                            tooltip: 'Replay audio',
                            icon: Icon(
                              _isPlayingAudio ? Icons.volume_up : Icons.play_arrow,
                              color: const Color(0xFF34D399),
                              size: 26,
                            ),
                            onPressed: _renderResult!.audioUrl != null
                                ? () => _playAudio(_renderResult!.audioUrl!)
                                : null,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'AI Voice Confirmation',
                                  style: TextStyle(
                                    color: Color(0xFF818CF8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  key: const Key('voice_confirmation_text'),
                                  '"${_renderResult!.voiceConfirmation}"',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const Divider(color: Colors.white12, height: 24),

                      // Extracted Summary Chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            label: Text(_renderResult!.room.type),
                            backgroundColor: const Color(0xFF0F172A),
                            labelStyle: const TextStyle(color: Colors.white, fontSize: 11),
                            padding: EdgeInsets.zero,
                          ),
                          Chip(
                            label: Text('${_renderResult!.room.surfaceM2} m²'),
                            backgroundColor: const Color(0xFF0F172A),
                            labelStyle: const TextStyle(color: Colors.white, fontSize: 11),
                            padding: EdgeInsets.zero,
                          ),
                          Chip(
                            label: Text(_renderResult!.style),
                            backgroundColor: const Color(0xFF0F172A),
                            labelStyle: const TextStyle(color: Color(0xFF818CF8), fontSize: 11),
                            padding: EdgeInsets.zero,
                          ),
                          Chip(
                            label: Text('${_renderResult!.workItems.length} work items'),
                            backgroundColor: const Color(0xFF0F172A),
                            labelStyle: const TextStyle(color: Color(0xFF34D399), fontSize: 11),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Primary CTA: Find renovators for this design
                ElevatedButton.icon(
                  key: const Key('find_renovators_button'),
                  onPressed: _onFindRenovatorsPressed,
                  icon: const Icon(Icons.search, size: 20),
                  label: const Text(
                    'Find renovators for this design',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Secondary button always visible: Skip design and use sample project
              OutlinedButton(
                key: const Key('skip_design_button'),
                onPressed: _onSkipDesignPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF94A3B8),
                  side: const BorderSide(color: Colors.white12),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Skip design and use sample project',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
