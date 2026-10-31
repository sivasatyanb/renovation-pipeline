import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/call_api_client.dart';
import '../services/call_handler.dart';
import 'results_screen.dart';

class ResearchScreen extends StatefulWidget {
  final Project project;
  final QuizAnswers answers;
  final String? afterRenderUrl;
  final ResearchApiClient? apiClient;
  final OnCallPressedCallback? onCallPressed;
  final CallApiClient? callApiClient;
  final CallAudioPlayer? audioPlayer;

  const ResearchScreen({
    super.key,
    required this.project,
    required this.answers,
    this.afterRenderUrl,
    this.apiClient,
    this.onCallPressed,
    this.callApiClient,
    this.audioPlayer,
  });

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  late final ResearchApiClient _apiClient;
  Timer? _pollTimer;
  String? _jobId;
  String _status = 'starting';
  String _phase = 'researching';
  String? _errorMessage;
  bool _isDisposed = false;

  static const List<Map<String, String>> _phaseDefinitions = [
    {
      'id': 'researching',
      'title': 'Deep Market Research',
      'desc': 'Finding local contractors in client city',
    },
    {
      'id': 'structuring',
      'title': 'Structuring Profiles',
      'desc': 'Extracting pricing, trades and credentials',
    },
    {
      'id': 'verifying',
      'title': 'Verifying Credentials',
      'desc': 'Checking phone numbers & insurance',
    },
    {
      'id': 'done',
      'title': 'Finalizing Recommendations',
      'desc': 'Ranking top qualifying renovators',
    },
  ];

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? HttpResearchApiClient();
    _startJob();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startJob() async {
    _pollTimer?.cancel();
    setState(() {
      _status = 'starting';
      _phase = 'researching';
      _errorMessage = null;
    });

    try {
      final jobId =
          await _apiClient.startResearch(widget.project, widget.answers);
      if (_isDisposed) return;

      setState(() {
        _jobId = jobId;
        _status = 'running';
      });

      // Poll immediately once, then start 5-second periodic polling
      await _checkStatus();
      if (_isDisposed || _status == 'completed' || _status == 'failed') return;

      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _checkStatus();
      });
    } catch (e) {
      if (_isDisposed) return;
      setState(() {
        _errorMessage = e.toString();
        _status = 'failed';
      });
    }
  }

  Future<void> _checkStatus() async {
    if (_jobId == null || _isDisposed) return;

    try {
      final statusResp = await _apiClient.getResearchStatus(_jobId!);
      if (_isDisposed) return;

      setState(() {
        _status = statusResp.status;
        _phase = statusResp.phase;
      });

      if (statusResp.isCompleted && statusResp.result != null) {
        _pollTimer?.cancel();
        if (!mounted) return;
        final renderUrl = widget.afterRenderUrl ??
            (widget.project.renderUrls.isNotEmpty
                ? widget.project.renderUrls.first
                : null);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultsScreen(
              jobId: _jobId ?? '',
              result: statusResp.result!,
              afterRenderUrl: renderUrl,
              project: widget.project,
              onCallPressed: widget.onCallPressed,
              callApiClient: widget.callApiClient,
              audioPlayer: widget.audioPlayer,
            ),
          ),
        );
      } else if (statusResp.isFailed) {
        _pollTimer?.cancel();
        setState(() {
          _errorMessage = statusResp.error ?? 'Research job failed.';
          _status = 'failed';
        });
      }
    } catch (e) {
      if (_isDisposed) return;
      _pollTimer?.cancel();
      setState(() {
        _errorMessage = 'Status check failed: $e';
        _status = 'failed';
      });
    }
  }

  int _getPhaseIndex(String phaseId) {
    for (int i = 0; i < _phaseDefinitions.length; i++) {
      if (_phaseDefinitions[i]['id'] == phaseId) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentPhaseIdx = _getPhaseIndex(_phase);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contractor Research'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                'Researching Contractors',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Searching ${widget.project.client.city} contractors for ${widget.project.style} ${widget.project.room.type}...',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_errorMessage != null) ...[
                Card(
                  color: Colors.red.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'An error occurred',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade800),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  key: const Key('retry_button'),
                  onPressed: _startJob,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ] else ...[
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: List.generate(_phaseDefinitions.length, (index) {
                        final phaseItem = _phaseDefinitions[index];
                        final isDone = index < currentPhaseIdx;
                        final isCurrent = index == currentPhaseIdx;
                        final isPending = index > currentPhaseIdx;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDone
                                      ? Colors.green
                                      : isCurrent
                                          ? Theme.of(context).primaryColor
                                          : Colors.grey.shade300,
                                ),
                                child: isDone
                                    ? const Icon(Icons.check,
                                        color: Colors.white, size: 20)
                                    : isCurrent
                                        ? const Center(
                                            child: SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                        Colors.white),
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Text(
                                              '${index + 1}',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      phaseItem['title']!,
                                      style: TextStyle(
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isPending
                                            ? Colors.grey.shade400
                                            : Colors.black87,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      phaseItem['desc']!,
                                      style: TextStyle(
                                        color: isPending
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const Spacer(),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text(
                      'This takes about 10-30 seconds',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
