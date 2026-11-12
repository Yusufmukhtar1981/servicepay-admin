import 'package:flutter/material.dart';

const Color executiveInk = Color(0xFF173B35);
const Color executiveGreen = Color(0xFF16834B);
const Color executiveMint = Color(0xFFE8F2EB);
const Color executiveCanvas = Color(0xFFF3F6F4);
const Color executiveMuted = Color(0xFF64756E);

class ExecutivePanel extends StatelessWidget {
  const ExecutivePanel({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFDFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCE6DF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: executiveInk)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          style: const TextStyle(
                              color: executiveMuted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (action != null) action!,
            ]),
            const SizedBox(height: 18),
            child,
          ],
        ),
      );
}

class ExecutiveMetric extends StatelessWidget {
  const ExecutiveMetric({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    this.onTap,
    this.emphasis = false,
  });
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      constraints: const BoxConstraints(minHeight: 130),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: emphasis ? executiveInk : const Color(0xFFFCFDFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: emphasis ? executiveInk : const Color(0xFFDCE6DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon,
                size: 18,
                color: emphasis ? const Color(0xFFAED9B8) : executiveGreen),
            const Spacer(),
            if (onTap != null)
              Icon(Icons.arrow_outward,
                  size: 15, color: emphasis ? Colors.white70 : executiveMuted),
          ]),
          const Spacer(),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 24,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: emphasis ? Colors.white : executiveInk)),
          const SizedBox(height: 5),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: emphasis ? Colors.white : executiveInk)),
          const SizedBox(height: 3),
          Text(note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: emphasis ? Colors.white70 : executiveMuted)),
        ],
      ),
    );
    return onTap == null
        ? card
        : Material(
            color: Colors.transparent,
            child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: card),
          );
  }
}

class ExecutiveSectionError extends StatelessWidget {
  const ExecutiveSectionError(
      {super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined,
                size: 32, color: executiveMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry section')),
          ]),
        ),
      );
}
