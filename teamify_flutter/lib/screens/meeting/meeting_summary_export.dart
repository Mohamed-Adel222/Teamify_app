import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a downloadable PDF for the meeting summary screen.
Future<Uint8List> buildMeetingSummaryPdf({
  required String roomName,
  required String summaryText,
  required List<String> decisions,
  required List<Map<String, String>> actions,
  String? durationLabel,
  int participantsCount = 0,
}) async {
  final doc = pw.Document();
  final meta = <String>[
    if (participantsCount > 0) '$participantsCount participants',
    if (durationLabel != null && durationLabel.isNotEmpty) durationLabel,
  ].join(' · ');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Text(
          'Meeting Summary',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(roomName, style: const pw.TextStyle(fontSize: 14)),
        if (meta.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(meta,
              style:
                  const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        ],
        if (summaryText.trim().isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text('Overview',
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(summaryText,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 4)),
        ],
        pw.SizedBox(height: 20),
        pw.Text('Decisions Made',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (decisions.isEmpty)
          pw.Text('No decisions captured.',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700))
        else
          ...decisions.map(
            (d) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('• ', style: const pw.TextStyle(fontSize: 11)),
                  pw.Expanded(
                      child: pw.Text(d,
                          style: const pw.TextStyle(
                              fontSize: 11, lineSpacing: 3))),
                ],
              ),
            ),
          ),
        pw.SizedBox(height: 16),
        pw.Text('Action Items',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (actions.isEmpty)
          pw.Text('No action items captured.',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700))
        else
          ...actions.map(
            (a) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    a['text'] ?? '',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(a['owner'] ?? 'Team',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey700)),
                      pw.Text(
                        a['due'] ?? 'TBD',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.orange800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  return Uint8List.fromList(await doc.save());
}

String meetingSummaryPdfFilename(String roomName) {
  final safe = roomName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  return 'meeting-summary-${safe.isEmpty ? 'teamify' : safe}-$stamp.pdf';
}
