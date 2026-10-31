import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/audio_player_service.dart';
import '../services/call_api_client.dart';

class CallScreen extends StatefulWidget {
  final String jobId;
  final Contractor contractor;
  final CallApiClient? callApiClient;
  final CallAudioPlayer? audioPlayer;
  final Duration pollInterval;

  const CallScreen({
    super.key,
    required this.jobId,
    required this.contractor,
    this.callApiClient,
    this.audioPlayer,
    this.pollInterval = const Duration(seconds: 1),
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallApiClient _callApiClient;
  late final CallAudioPlayer _audioPlayer;

  late final TextEditingController _emailController;
  late final TextEditingController _addressController;

  Timer? _pollTimer;
  String? _callId;
  CallStatusResponse? _statusResponse;

  bool _isCallStarted = false;
  bool _isStopped = false;
  String? _errorMessage;

  int _nextAfterIndex = 0;
  final List<CallTurn> _turnQueue = [];
  final List<CallTurn> _visibleTurns = [];
  bool _isProcessingQueue = false;

  @override
  void initState() {
    super.initState();
    _callApiClient = widget.callApiClient ?? HttpCallApiClient();
    _audioPlayer = widget.audioPlayer ?? AudioplayersCallAudioPlayer();

    _emailController =
        TextEditingController(text: 'demo.customer@example.com');
    _addressController =
        TextEditingController(text: '12 Rue de Rivoli, 75004 Paris, France');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _isStopped = true;
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _startCall() async {
    setState(() {
      _isCallStarted = true;
      _errorMessage = null;
    });

    try {
      final request = CallRequest(
        jobId: widget.jobId,
        contractorId: widget.contractor.id,
        meeting: MeetingRequest(
          customerEmail: _emailController.text.trim(),
          address: _addressController.text.trim(),
          slots: const [],
        ),
      );

      final callId = await _callApiClient.startCall(request);
      if (!mounted) return;

      setState(() {
        _callId = callId;
      });

      // Poll immediately once, then periodically
      await _pollStatus();
      if (!mounted || _isStopped) return;

      _pollTimer = Timer.periodic(widget.pollInterval, (_) {
        _pollStatus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _pollStatus() async {
    if (_callId == null || _isStopped) return;

    try {
      final response = await _callApiClient.getCallStatus(
        _callId!,
        after: _nextAfterIndex,
      );
      if (!mounted || _isStopped) return;

      setState(() {
        _statusResponse = response;
      });

      if (response.turns.isNotEmpty) {
        for (final t in response.turns) {
          if (t.index >= _nextAfterIndex) {
            _nextAfterIndex = t.index + 1;
            _turnQueue.add(t);
          }
        }
        _processTurnQueue();
      }

      if (response.isTerminal) {
        _pollTimer?.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Polling error: $e');
    }
  }

  Future<void> _processTurnQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_turnQueue.isNotEmpty && mounted && !_isStopped) {
      final turn = _turnQueue.removeAt(0);
      setState(() {
        _visibleTurns.add(turn);
      });

      if (turn.audioUrl != null && turn.audioUrl!.isNotEmpty) {
        try {
          final resolvedUrl = _callApiClient.resolveAudioUrl(turn.audioUrl!);
          await _audioPlayer.playUrl(resolvedUrl);
        } catch (e) {
          debugPrint('Audio playback error: $e');
        }
      }
    }

    _isProcessingQueue = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _stopCall() async {
    _isStopped = true;
    _pollTimer?.cancel();
    _turnQueue.clear();

    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }

    if (_callId != null) {
      try {
        final resp = await _callApiClient.stopCall(_callId!);
        if (mounted) {
          setState(() {
            _statusResponse = resp;
          });
        }
      } catch (e) {
        debugPrint('Error stopping call: $e');
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Could not launch $url: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusResponse?.status ?? (_isCallStarted ? 'starting' : 'idle');
    final phase = _statusResponse?.phase ?? 'negotiating';
    final isReplay = _statusResponse?.isReplay == true ||
        (_statusResponse?.warnings.any((w) => w.contains('Replay')) ?? false);

    final isTerminal = _statusResponse?.isTerminal == true || _isStopped;
    final isCallDone = isTerminal && _turnQueue.isEmpty && !_isProcessingQueue;
    final isActive = _isCallStarted && !isCallDone;

    return Scaffold(
      appBar: AppBar(
        title: Text('Call with ${widget.contractor.name}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Permanent top disclaimer banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.blueGrey.shade800,
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Simulated call: AI customer agent and AI renovator agent',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isReplay)
                    Container(
                      key: const Key('replay_badge'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade400,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Replay',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Pre-call form
            if (!_isCallStarted)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Meeting Information',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                key: const Key('call_email_field'),
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Customer Email',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                keyboardType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                key: const Key('call_address_field'),
                                controller: _addressController,
                                decoration: const InputDecoration(
                                  labelText: 'Meeting Address',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        key: const Key('start_call_button'),
                        onPressed: _startCall,
                        icon: const Icon(Icons.phone_in_talk),
                        label: const Text('Start Call'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // During & after call view
            if (_isCallStarted) ...[
              // Status & phase banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    Text(
                      'Phase: $phase',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Status: $status',
                      style: TextStyle(
                        color: status == 'completed'
                            ? Colors.green.shade700
                            : status == 'failed'
                                ? Colors.red.shade700
                                : Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (isActive)
                      OutlinedButton.icon(
                        key: const Key('stop_call_button'),
                        onPressed: _stopCall,
                        icon: const Icon(Icons.stop, color: Colors.red, size: 18),
                        label: const Text('Stop', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),

              // Live transcript
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _visibleTurns.length + (isCallDone ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < _visibleTurns.length) {
                      final turn = _visibleTurns[index];
                      final isCustomer = turn.speaker == 'customer_agent';
                      final speakerName =
                          isCustomer ? 'Customer Agent' : 'Renovator Agent';

                      return Align(
                        alignment: isCustomer
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.8,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isCustomer
                                ? Colors.blue.shade50
                                : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCustomer
                                  ? Colors.blue.shade200
                                  : Colors.teal.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                speakerName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isCustomer
                                      ? Colors.blue.shade900
                                      : Colors.teal.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                turn.text,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // Completion Summary Card
                    return _buildCompletionSummary();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionSummary() {
    final outcome = _statusResponse?.outcome;
    final match = _statusResponse?.match;
    final booking = _statusResponse?.booking;

    final curr = outcome?.currency ?? '';
    final openStr = outcome?.openingPrice != null ? '${outcome!.openingPrice} $curr' : 'N/A';
    final finalStr = outcome?.finalPrice != null ? '${outcome!.finalPrice} $curr' : 'N/A';
    final saveStr = outcome?.savings != null ? '${outcome!.savings} $curr' : 'N/A';

    return Card(
      key: const Key('call_summary_card'),
      margin: const EdgeInsets.only(top: 16, bottom: 24),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assessment_outlined, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(
                  'Negotiation Summary',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Pricing details
            if (outcome != null) ...[
              Text(
                '$openStr -> $finalStr (Saved $saveStr)',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _priceColumn('Opening Price', openStr),
                  _priceColumn('Final Price', finalStr),
                  _priceColumn('Savings', saveStr, highlight: true),
                ],
              ),
              if (outcome.agreedSlot != null) ...[
                const SizedBox(height: 8),
                Text('Agreed Slot: ${outcome.agreedSlot}',
                    style: TextStyle(color: Colors.grey.shade700)),
              ],
              const Divider(height: 24),
            ],

            // Match determination
            if (match != null) ...[
              Row(
                children: [
                  Icon(
                    match.match ? Icons.check_circle : Icons.cancel,
                    color: match.match ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    match.match ? 'Match' : 'No Match',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: match.match ? Colors.green.shade800 : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
              if (match.reasons.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...match.reasons.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(left: 32, top: 2),
                    child: Text('• $r', style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
              const Divider(height: 24),
            ],

            // Booking outcome
            if (booking != null) ...[
              Text(
                'Meeting Result: ${booking.status}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (booking.startsAt != null) ...[
                const SizedBox(height: 4),
                Text('Starts At: ${booking.startsAt}'),
              ],
              if (booking.location != null) ...[
                const SizedBox(height: 4),
                Text('Location: ${booking.location}'),
              ],
              if (booking.eventUrl != null && booking.eventUrl!.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  key: const Key('booking_event_link'),
                  onTap: () => _openUrl(booking.eventUrl!),
                  child: Text(
                    booking.eventUrl!,
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              if (booking.warnings.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...booking.warnings.map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Warning: $w',
                        style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _priceColumn(String title, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: highlight ? Colors.green.shade700 : Colors.black87,
          ),
        ),
      ],
    );
  }
}
