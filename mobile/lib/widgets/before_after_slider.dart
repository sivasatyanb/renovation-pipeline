import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Interactive Before / After Split-Screen Comparator Widget.
///
/// Displays the "After" renovated space as the base layer, with the "Before"
/// site photo clipped horizontally on top. Supports horizontal drag gestures
/// as well as an accessible direct Slider controller (`Key('before_after_slider')`).
class BeforeAfterSlider extends StatefulWidget {
  final Uint8List? beforeBytes;
  final String? beforeImageUrl;
  final Uint8List? afterBytes;
  final String? afterImageUrl;
  final double initialPercent;
  final ValueChanged<double>? onPositionChanged;
  final double height;

  const BeforeAfterSlider({
    super.key,
    this.beforeBytes,
    this.beforeImageUrl,
    this.afterBytes,
    this.afterImageUrl,
    this.initialPercent = 50.0,
    this.onPositionChanged,
    this.height = 320.0,
  });

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  late double _percent;

  @override
  void initState() {
    super.initState();
    _percent = widget.initialPercent;
  }

  @override
  void didUpdateWidget(BeforeAfterSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPercent != widget.initialPercent) {
      _percent = widget.initialPercent;
    }
  }

  void _updatePosition(double newPercent) {
    final clamped = newPercent.clamp(0.0, 100.0);
    setState(() {
      _percent = clamped;
    });
    widget.onPositionChanged?.call(clamped);
  }

  Widget _buildImage({
    Uint8List? bytes,
    String? url,
    required String fallbackLabel,
  }) {
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, error, stackTrace) => _buildFallback(fallbackLabel),
      );
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, error, stackTrace) => _buildFallback(fallbackLabel),
      );
    }
    return _buildFallback(fallbackLabel);
  }

  Widget _buildFallback(String label) {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, color: Colors.white54, size: 40),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final dividerX = (width * (_percent / 100.0)).clamp(0.0, width);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                if (width > 0) {
                  final newPercent =
                      ((details.localPosition.dx) / width) * 100.0;
                  _updatePosition(newPercent);
                }
              },
              child: SizedBox(
                height: widget.height,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base layer: AFTER renovated room
                      _buildImage(
                        bytes: widget.afterBytes,
                        url: widget.afterImageUrl,
                        fallbackLabel: 'After Renovation',
                      ),

                      // Clipped layer: BEFORE site photo
                      ClipRect(
                        clipper: _HorizontalSplitClipper(_percent),
                        child: _buildImage(
                          bytes: widget.beforeBytes,
                          url: widget.beforeImageUrl,
                          fallbackLabel: 'Before Renovation',
                        ),
                      ),

                      // BEFORE badge overlay
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Text(
                            'Before',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                      // AFTER badge overlay
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white38),
                          ),
                          child: const Text(
                            'After',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                      // Split Divider Line
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: dividerX - 1.5,
                        child: Container(
                          width: 3.0,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF818CF8),
                                Colors.white,
                                Color(0xFF38BDF8),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.8),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Center Drag Handle
                      Positioned(
                        top: (widget.height / 2) - 20,
                        left: dividerX - 20,
                        child: Container(
                          key: const Key('slider_drag_handle'),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.compare_arrows,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        // Accessible direct slider control
        Slider(
          key: const Key('before_after_slider'),
          value: _percent,
          min: 0.0,
          max: 100.0,
          activeColor: const Color(0xFF6366F1),
          inactiveColor: Colors.grey.shade300,
          onChanged: _updatePosition,
        ),
      ],
    );
  }
}

class _HorizontalSplitClipper extends CustomClipper<Rect> {
  final double percent;

  _HorizontalSplitClipper(this.percent);

  @override
  Rect getClip(Size size) {
    final clippedWidth = (size.width * (percent / 100.0)).clamp(0.0, size.width);
    return Rect.fromLTWH(0, 0, clippedWidth, size.height);
  }

  @override
  bool shouldReclip(_HorizontalSplitClipper oldClipper) {
    return oldClipper.percent != percent;
  }
}
