import 'package:flutter/material.dart';

class StageBackground extends StatelessWidget {
  final Widget child;

  const StageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6F3EA), Color(0xFFE8E2D3)],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -80,
          child: _GlowCircle(
            size: 280,
            color: const Color(0xFFC58545).withValues(alpha: 0.20),
          ),
        ),
        Positioned(
          right: -90,
          bottom: -120,
          child: _GlowCircle(
            size: 320,
            color: const Color(0xFF102A43).withValues(alpha: 0.12),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF102A43).withValues(alpha: 0.03),
              backgroundBlendMode: BlendMode.multiply,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class AppPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Border? border;

  const AppPanel({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border:
            border ??
            Border.all(color: const Color(0xFF102A43).withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1E102A43),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
