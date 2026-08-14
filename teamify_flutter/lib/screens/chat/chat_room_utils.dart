import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_result.dart';
import '../../core/observability/app_logger.dart';
import '../../core/routes.dart';
import '../../data/models/api_user.dart';
import '../../models/models.dart';
import '../../services/app_services.dart';

ChatRoom chatRoomFromApi(Map<String, dynamic> json) {
  final name = json['name']?.toString().trim();
  final displayName =
      (name != null && name.isNotEmpty) ? name : 'Chat ${json['id']}';
  final last = json['last_message'];
  var lastMessage = 'No messages yet';
  var time = '';
  if (last is Map<String, dynamic>) {
    lastMessage = last['content']?.toString() ?? lastMessage;
    lastMessage = _previewChatContent(
      lastMessage,
      last['message_type']?.toString(),
    );
    final sender = last['sender_name']?.toString();
    if (sender != null && sender.isNotEmpty) {
      lastMessage = '$sender: $lastMessage';
    }
    final created = last['created_at']?.toString() ?? '';
    if (created.isNotEmpty) {
      time = created.contains('T')
          ? created.split('T').last.split('.').first
          : created;
    }
  }
  final parts =
      displayName.split(' ').where((part) => part.isNotEmpty).toList();
  final initials = parts.take(2).map((part) => part[0].toUpperCase()).join();
  return ChatRoom(
    id: json['id'].toString(),
    name: displayName,
    lastMessage: lastMessage,
    time: time.isNotEmpty ? time : '—',
    initials: initials.isNotEmpty ? initials : 'CH',
    isGroup: json['is_group'] == true,
    projectId: json['project_id']?.toString(),
  );
}

String? projectIdFromChatRoomPayload(Map<String, dynamic> data) {
  final room = data['room'];
  if (room is Map) {
    final nested = room['project_id']?.toString();
    if (nested != null && nested.isNotEmpty) return nested;
  }
  final flat = data['project_id']?.toString();
  if (flat != null && flat.isNotEmpty) return flat;
  return null;
}

String _previewChatContent(String content, String? messageType) {
  switch (messageType) {
    case 'image':
      return 'Photo';
    case 'video':
      return 'Video';
    case 'audio':
      return 'Voice message';
    case 'file':
      return 'Document';
    case 'poll':
    case 'event':
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          return (decoded['question'] ?? decoded['title'] ?? messageType)
              .toString();
        }
      } catch (_) {}
      return messageType ?? content;
    default:
      return content;
  }
}

/// Opens (or creates) the team chat room for a project and navigates to it.
Future<void> openProjectTeamChat(
  BuildContext context, {
  required String projectId,
  required String projectName,
}) async {
  final projectIdInt = int.tryParse(projectId);
  if (projectIdInt == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invalid project id')),
    );
    return;
  }

  try {
    final roomMap = await context.read<AppServices>().chat.createRoom({
      'name': projectName,
      'project_id': projectIdInt,
      'is_group': true,
    }).unwrap();
    if (!context.mounted) return;
    Navigator.pushNamed(
      context,
      R.groupChat,
      arguments: chatRoomFromApi(roomMap),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open team chat: $e')),
      );
    }
  }
}

/// Opens (or creates) a 1:1 DM with [user] using a real numeric room id.
Future<void> openDirectChat(BuildContext context, ApiUser user) async {
  final peerId = int.tryParse(user.id);
  if (peerId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invalid user id')),
    );
    return;
  }

  try {
    final roomMap = await context
        .read<AppServices>()
        .chat
        .findOrCreateDirect(peerId)
        .unwrap();
    if (!context.mounted) return;
    final room = chatRoomFromApi(roomMap);
    Navigator.pushNamed(
      context,
      R.directChat,
      arguments: ChatRoom(
        id: room.id,
        name: user.primaryName.isNotEmpty ? user.primaryName : room.name,
        lastMessage: room.lastMessage,
        time: room.time,
        initials: user.initials.isNotEmpty ? user.initials : room.initials,
        isGroup: false,
        projectId: room.projectId,
      ),
    );
  } catch (e) {
    AppLogger.error('Could not open direct chat', e);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open conversation: $e')),
      );
    }
  }
}
