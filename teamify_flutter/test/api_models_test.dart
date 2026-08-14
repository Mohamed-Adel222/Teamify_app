import 'package:flutter_test/flutter_test.dart';
import 'package:teamify/data/models/models.dart';

void main() {
  test('ApiUser parses numeric ids and snake_case fields', () {
    final user = ApiUser.fromJson({
      'id': 42,
      'display_name': 'matti',
      'full_name': 'Matti Weber',
      'email': 'matti@example.com',
      'role': 'member',
      'user_type': 'freelancer',
      'skills': ['Flutter', 'Dart'],
    });

    expect(user.id, '42');
    expect(user.isPending, isFalse);
    expect(user.displayRole, 'Freelancer');
    expect(user.skills, ['Flutter', 'Dart']);
  });

  test('ApiUser projectRoleLabel uses backend project_role', () {
    final owner = ApiUser.fromJson({
      'id': 1,
      'display_name': 'm.adel01f',
      'full_name': 'Mohamed Adel',
      'email': 'm@example.com',
      'role': 'member',
      'project_role': 'owner',
      'user_type': 'freelancer',
    });
    expect(owner.projectRoleLabel, 'Owner');
    expect(owner.primaryName, 'Mohamed Adel');
    expect(owner.displayName, 'm.adel01f');
  });

  test('ApiProject and ApiTask tolerate nullable backend fields', () {
    final project = ApiProject.fromJson({
      'id': 7,
      'name': 'Backend Integration',
      'description': null,
      'status': 'active',
      'tasks': [
        {'id': 3, 'title': 'Wire Flutter', 'project_id': 7}
      ],
    });

    expect(project.id, '7');
    expect(project.tasks.single.id, '3');
    expect(project.tasks.single.projectId, '7');
  });

  test('ApiNotification maps email_delivered from the backend', () {
    final sent = ApiNotification.fromJson({
      'id': 9,
      'title': 'Task assigned',
      'body': 'You have a new task',
      'is_read': false,
      'type': 'task_assigned',
      'email_delivered': true,
      'email_status': 'sent',
      'entity_type': 'Task',
      'entity_id': 201,
    });
    expect(sent.emailDelivered, isTrue);
    expect(sent.emailStatus, 'sent');
    expect(sent.hasLinkedEntity, isTrue);

    final inAppOnly = ApiNotification.fromJson({
      'id': 10,
      'title': 'Task assigned',
      'type': 'task_assigned',
    });
    expect(inAppOnly.emailDelivered, isFalse);
    expect(inAppOnly.hasLinkedEntity, isFalse);
  });
}
