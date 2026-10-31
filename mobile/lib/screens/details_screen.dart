import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/audio_player_service.dart';
import '../services/call_api_client.dart';
import '../services/call_handler.dart';
import 'call_screen.dart';

class DetailsScreen extends StatelessWidget {
  final String jobId;
  final Contractor contractor;
  final OnCallPressedCallback? onCallPressed;
  final CallApiClient? callApiClient;
  final CallAudioPlayer? audioPlayer;

  const DetailsScreen({
    super.key,
    this.jobId = '',
    required this.contractor,
    this.onCallPressed,
    this.callApiClient,
    this.audioPlayer,
  });

  void _onCall(BuildContext context) {
    debugPrint('Call pressed for contractor: ${contractor.id}');
    if (onCallPressed != null) {
      onCallPressed!(contractor);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            jobId: jobId,
            contractor: contractor,
            callApiClient: callApiClient,
            audioPlayer: audioPlayer,
          ),
        ),
      );
    }
  }

  Future<void> _launchUrlString(BuildContext context, String url) async {
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
    final sub = contractor.subscores;

    return Scaffold(
      appBar: AppBar(
        title: Text(contractor.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              key: const Key('details_call_button'),
              onPressed: () => _onCall(context),
              icon: const Icon(Icons.phone, color: Colors.green),
              label: const Text(
                'Call',
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Header Card
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Rank #${contractor.rank}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Text(
                          'Overall Score: ${contractor.score.toInt()}/100',
                          style: TextStyle(
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    contractor.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  if (contractor.address != null)
                    Text(
                      contractor.address!,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: contractor.trades
                        .map((t) => Chip(
                              label: Text(t),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Subscores Breakdown
          Card(
            key: const Key('subscores_card'),
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
                    'Score Breakdown',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _buildScoreTile('Price', sub.price.toInt())),
                      Expanded(
                          child: _buildScoreTile(
                              'Reputation', sub.reputation.toInt())),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildScoreTile('Fit', sub.fit.toInt())),
                      Expanded(
                          child: _buildScoreTile(
                              'Availability', sub.availability.toInt())),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Contact & Verification Card
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
                    'Contact & Verification',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        contractor.phoneE164,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: contractor.phoneVerified
                              ? Colors.green.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          contractor.phoneVerified
                              ? 'Phone verified'
                              : 'Phone unverified',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: contractor.phoneVerified
                                ? Colors.green.shade900
                                : Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (contractor.phoneSourceUrl != null) ...[
                    const SizedBox(height: 6),
                    _buildTappableLink(
                      context,
                      label: 'Phone Source URL',
                      url: contractor.phoneSourceUrl!,
                    ),
                  ],
                  if (contractor.website != null) ...[
                    const SizedBox(height: 8),
                    _buildTappableLink(
                      context,
                      label: 'Official Website',
                      url: contractor.website!,
                    ),
                  ],
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        contractor.rating != null
                            ? '${contractor.rating} (${contractor.reviewCount ?? 0} reviews)'
                            : 'No rating found',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        contractor.availability ?? 'Availability not specified',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.euro, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        contractor.expectedPrice != null
                            ? '${contractor.expectedPrice!.low ?? 'N/A'} - ${contractor.expectedPrice!.high ?? 'N/A'} ${contractor.expectedPrice!.currency}'
                            : 'Price not found',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Why Recommended
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
                    'Why Recommended',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    contractor.whyRecommended,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Red Flags Section
          if (contractor.redFlags.isNotEmpty)
            Card(
              key: const Key('red_flags_card'),
              color: Colors.red.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.red.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flag, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Red Flags & Points to Note',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...contractor.redFlags.map(
                      (flag) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(
                                flag,
                                style: TextStyle(
                                    color: Colors.red.shade900, fontSize: 13),
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
          if (contractor.redFlags.isNotEmpty) const SizedBox(height: 12),

          // Insurance & Certifications
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
                    'Insurance & Credentials',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (contractor.insurance != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.shield_outlined,
                            size: 18, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            contractor.insurance!,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (contractor.certifications.isNotEmpty) ...[
                    const Text('Certifications:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    ...contractor.certifications.map(
                      (cert) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: cert.sourceUrl != null
                            ? _buildTappableLink(
                                context,
                                label: cert.name,
                                url: cert.sourceUrl!,
                              )
                            : Text('• ${cert.name}',
                                style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Portfolio URLs
          if (contractor.portfolioUrls.isNotEmpty)
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
                      'Portfolio & Projects',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...contractor.portfolioUrls.map((url) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: _buildTappableLink(context,
                              label: url, url: url),
                        )),
                  ],
                ),
              ),
            ),
          if (contractor.portfolioUrls.isNotEmpty) const SizedBox(height: 12),

          // Call Brief Card
          if (contractor.callBrief != null)
            Card(
              key: const Key('call_brief_card'),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mic, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Call Brief for Bargaining',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Target: ${contractor.callBrief!.targetPrice != null ? '€${contractor.callBrief!.targetPrice}' : 'N/A'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Max: ${contractor.callBrief!.maxPrice != null ? '€${contractor.callBrief!.maxPrice}' : 'N/A'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    const Text('Leverage Points:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    ...contractor.callBrief!.leveragePoints.map(
                      (p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(p,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Questions to Ask:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    ...contractor.callBrief!.questionsToAsk.map(
                      (q) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('? ',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo)),
                            Expanded(
                              child: Text(q,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (contractor.callBrief != null) const SizedBox(height: 12),

          // Source URLs
          if (contractor.sourceUrls.isNotEmpty)
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
                      'Research Source Links',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...contractor.sourceUrls.map((url) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: _buildTappableLink(context,
                              label: url, url: url),
                        )),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Bottom Call Button
          ElevatedButton.icon(
            key: const Key('details_bottom_call_button'),
            onPressed: () => _onCall(context),
            icon: const Icon(Icons.phone),
            label: const Text('Call Contractor'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
  }

  Widget _buildScoreTile(String label, int score) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '$score/100',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildTappableLink(
    BuildContext context, {
    required String label,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchUrlString(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}