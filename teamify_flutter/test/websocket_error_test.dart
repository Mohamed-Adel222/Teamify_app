import 'package:flutter_test/flutter_test.dart';
import 'package:teamify/core/network/websocket_manager.dart';
import 'package:teamify/data/models/notification_preferences_model.dart';

void main() {
  group('userFacingSocketError', () {
    test('swallows TransportError maps shown as minified dart2js objects', () {
      const raw = {
        'msg': 'websocket error',
        'desc': 'Instance of \'minified:c2\'',
        'type': 'TransportError',
      };
      expect(isTransportSocketError(raw), isTrue);
      expect(userFacingSocketError(raw), isEmpty);
      expect(
        isTransportSocketError(
          '{msg: websocket error, desc: Instance of \'minified:c2\', type: TransportError}',
        ),
        isTrue,
      );
      expect(
        userFacingSocketError(
          '{msg: websocket error, desc: Instance of \'minified:c2\', type: TransportError}',
        ),
        isEmpty,
      );
    });

    test('keeps real chat errors', () {
      expect(userFacingSocketError('Message too long'), 'Message too long');
      expect(
        isTransportSocketError({'message': 'You are not in this room'}),
        isFalse,
      );
    });
  });

  group('NotificationType.fromString', () {
    test('maps deadline_approaching to deadline reminder', () {
      expect(
        NotificationTypeX.fromString('deadline_approaching'),
        NotificationType.deadlineReminder,
      );
    });

    test('maps connection_request without treating it as a chat message', () {
      expect(
        NotificationTypeX.fromString('connection_request'),
        NotificationType.systemNotification,
      );
    });
  });
}
