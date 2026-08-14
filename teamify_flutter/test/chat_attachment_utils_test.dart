import 'package:flutter_test/flutter_test.dart';
import 'package:teamify/screens/chat/chat_attachment_utils.dart';

void main() {
  test('parseStructuredPayload reads poll JSON from content', () {
    const json =
        '{"question":"Lunch?","options":[{"text":"Pizza","votes":0}]}';
    final data = parseStructuredPayload(content: json);
    expect(data, isNotNull);
    expect(data!['question'], 'Lunch?');
  });

  test('parseStructuredPayload recovers JSON stuffed into fileId', () {
    const json = '{"title":"Design sync","dateStr":"2026-8-14"}';
    final data = parseStructuredPayload(content: 'Design sync', fileId: json);
    expect(data!['title'], 'Design sync');
  });

  test('parseNumericFileId rejects filenames', () {
    expect(parseNumericFileId('camera_photo.jpg'), isNull);
    expect(parseNumericFileId('42'), 42);
  });

  test('isVideoFilename detects common video extensions', () {
    expect(isVideoFilename('clip.mp4'), isTrue);
    expect(isVideoFilename('photo.jpg'), isFalse);
  });
}
