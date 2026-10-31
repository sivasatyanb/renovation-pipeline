import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/audio_player_service.dart';
import '../services/call_api_client.dart';
import '../services/call_handler.dart';
import 'call_screen.dart';
import 'details_screen.dart';

class ResultsScreen extends StatefulWidget {
  final String jobId;
  final ResearchResult result;
  final String? afterRenderUrl;
  final Project? project;
  final OnCallPressedCallback? onCallPressed;
  final CallApiClient? callApiClient;
  final CallAudioPlayer? audioPlayer;

  const ResultsScreen({
    super.key,
    this.jobId = '',
    required this.result,
    this.afterRenderUrl,
    this.project,
    this.onCallPressed,
    this.callApiClient,
    this.audioPlayer,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  void _onCall(Contractor contractor) {
    debugPrint('Call pressed for contractor: ${contractor.id}');
    if (widget.onCallPressed != null) {
      widget.onCallPressed!(contractor);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            jobId: widget.jobId,
            contractor: contractor,
            callApiClient: widget.callApiClient,
            audioPlayer: widget.audioPlayer,
          ),
        ),
      );
    }
  }

  void _openDetails(Contractor contractor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          jobId: widget.jobId,
          contractor: contractor,
          onCallPressed: widget.onCallPressed,
          callApiClient: widget.callApiClient,
          audioPlayer: widget.audioPlayer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final isDemoData = result.isDemo ||
        result.warnings.any((w) =>
            w.toLowerCase().contains('demo data') || w.contains('DEMO DATA'));

    final renderUrl = widget.afterRenderUrl ??
        (widget.project?.renderUrls.isNotEmpty == true
            ? widget.project!.renderUrls.first
            : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vetted Contractors'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Renovation Design Preview Banner
            if (renderUrl != null && renderUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Container(
                  key: const Key('results_render_preview'),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(11)),
                        child: Image.network(
                          renderUrl,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stackTrace) => Container(
                            height: 80,
                            color: const Color(0xFF1E293B),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.auto_awesome,
                                    color: Color(0xFF818CF8), size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Renovated Space Preview',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 8.0),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Color(0xFF059669), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Your Renovation Design',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Demo Data Banner / Chip
            if (isDemoData)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Container(
                  key: const Key('demo_data_banner'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.science, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Demo data',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Price Estimate Card
            Card(
              key: const Key('price_estimate_card'),
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
                        Icon(Icons.payments_outlined,
                            color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Estimated Project Price',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${result.priceEstimate.low ?? 'N/A'} - ${result.priceEstimate.high ?? 'N/A'} ${result.priceEstimate.currency}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                    ),
                    if (result.priceEstimate.lineItems.isNotEmpty) ...[
                      const Divider(height: 24),
                      Text(
                        'Line Items',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...result.priceEstimate.lineItems.map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(item.label,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.low ?? ''} - ${item.high ?? ''} ${result.priceEstimate.currency}',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Warnings Card
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                key: const Key('warnings_card'),
                color: Colors.amber.shade50,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.amber.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.amber.shade800, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            'Notice',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...result.warnings.map(
                        (warning) => Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            '• $warning',
                            style: TextStyle(
                                color: Colors.amber.shade900, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            Text(
              'Top Ranked Renovators (${result.contractors.length})',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),

            // Contractor Cards
            ...result.contractors.map((contractor) {
              final priceText = contractor.expectedPrice != null
                  ? '${contractor.expectedPrice!.low ?? 'N/A'} - ${contractor.expectedPrice!.high ?? 'N/A'} ${contractor.expectedPrice!.currency}'
                  : 'Price on request';

              return Card(
                key: Key('contractor_card_${contractor.id}'),
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openDetails(contractor),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              child: Text(
                                '#${contractor.rank}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    contractor.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (contractor.rating != null)
                                    Row(
                                      children: [
                                        const Icon(Icons.star,
                                            size: 16, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${contractor.rating} (${contractor.reviewCount ?? 0} reviews)',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black87),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Text(
                                'Score: ${contractor.score.toInt()}/100',
                                style: TextStyle(
                                  color: Colors.green.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.sell_outlined,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                              priceText,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.phone,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                              contractor.phoneE164,
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(width: 10),
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
                        const SizedBox(height: 10), 
                        Text( 
                          contractor.whyRecommended, 
                          style: TextStyle( 
                            fontSize: 13, 
                            color: Colors.grey.shade800, 
                          ), 
                        ), 
                        const SizedBox(height: 14), 
                        Row( 
                          mainAxisAlignment: MainAxisAlignment.end, 
                          children: [ 
                            OutlinedButton( 
                              onPressed: () => _openDetails(contractor), 
                              child: const Text('View Details'), 
                            ), 
                            const SizedBox(width: 10), 
                            ElevatedButton.icon( 
                              key: Key('call_button_${contractor.id}'), 
                              onPressed: () => _onCall(contractor), 
                              icon: const Icon(Icons.phone, size: 16), 
                              label: const Text('Call'), 
                              style: ElevatedButton.styleFrom( 
                                backgroundColor: Colors.green.shade700, 
                                foregroundColor: Colors.white, 
                              ), 
                            ), 
                          ], 
                        ), 
                      ], 
                    ), 
                  ), 
                ), 
              ); 
            }), 
          ], 
        ), 
      ), 
    ); 
  } 
}
