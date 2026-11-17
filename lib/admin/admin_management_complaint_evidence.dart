import 'dart:convert';
import 'package:flutter/material.dart';

/// Private evidence delivered by the existing, permission-checked Support API.
/// Never fetch arbitrary attachment URLs or render HTML from a complaint.
class AdminManagementComplaintEvidence extends StatelessWidget {
  const AdminManagementComplaintEvidence({super.key, required this.ticket});
  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final issue = ticket['managementIssueCategory']?.toString();
    final attachments = ticket['managementAttachments'] is List
        ? (ticket['managementAttachments'] as List).whereType<Map>().take(8)
        : const <Map>[];
    if (issue == null && attachments.isEmpty) return const SizedBox.shrink();
    final author = ticket['createdBy'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Management customer complaint',
              style: TextStyle(fontWeight: FontWeight.bold)),
          if (issue != null) Text(issue.replaceAll('_', ' ')),
          if (author is Map && author['fullName'] != null)
            Text('Submitted by ${author['fullName']} · ${author['role'] ?? ''}'),
          ...attachments.map(_image),
        ],
      ),
    );
  }

  Widget _image(Map attachment) {
    final data = attachment['dataUrl']?.toString() ?? '';
    if (data.length > 349600) return const SizedBox.shrink();
    final match =
        RegExp(r'^data:image/(png|jpeg|webp);base64,([A-Za-z0-9+/]+={0,2})$')
            .firstMatch(data);
    if (match == null) return const SizedBox.shrink();
    try {
      final bytes = base64Decode(match.group(2)!);
      if (bytes.isEmpty || bytes.length > 262144) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${attachment['name'] ?? 'Screenshot'}'),
            const SizedBox(height: 4),
            Image.memory(bytes,
                height: 200,
                cacheWidth: 800,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Text('Screenshot could not be displayed.')),
          ],
        ),
      );
    } on FormatException {
      return const SizedBox.shrink();
    }
  }
}
