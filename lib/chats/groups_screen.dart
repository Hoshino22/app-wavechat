import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wavechat/chats/group_chat_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:wavechat/utils/color_helper.dart';
import 'package:wavechat/utils/ui_helper.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({Key? key}) : super(key: key);

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _auth = FirebaseAuth.instance;
  final _groupNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('en', timeago.EnMessages());
    timeago.setLocaleMessages('en_short', timeago.EnShortMessages());
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('groups').add({
        'groupName': _groupNameController.text.trim(),
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'members': [user.uid],
        'lastMessage': 'Group created.',
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastMessageSenderId': user.uid,
      });

      _groupNameController.clear();
      if (mounted) {
        Navigator.of(context).pop();
        showStyledSnackBar(context, 'Group created successfully!');
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Failed to create group: $e', isError: true);
      }
    }
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create a New Group'),
          content: TextField(
            controller: _groupNameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter group name'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _groupNameController.clear();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: _createGroup,
              child: const Text('Create', style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupSubtitle(Map<String, dynamic> groupData, bool isLastMessageFromMe) {
    final currentUser = _auth.currentUser;
    final lastMessage = groupData['lastMessage'] as String?;
    final lastMessageSenderId = groupData['lastMessageSenderId'] as String?;

    final subtitleStyle = TextStyle(
      color: isLastMessageFromMe ? Colors.grey : Colors.black87,
      fontWeight: !isLastMessageFromMe ? FontWeight.bold : FontWeight.normal,
    );

    if (lastMessage == null || lastMessageSenderId == null || currentUser == null) {
      final memberCount = (groupData['members'] as List?)?.length ?? 0;
      return Text('$memberCount members', style: const TextStyle(color: Colors.grey));
    }

    if (isLastMessageFromMe) {
      return Text(
        'You: $lastMessage',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: subtitleStyle,
      );
    } else {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(lastMessageSenderId).get(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.done && userSnapshot.hasData) {
            final senderData = userSnapshot.data!.data() as Map<String, dynamic>;
            final senderName = senderData['fullName'] as String? ?? 'Someone';
            return Text(
              '$senderName: $lastMessage',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            );
          }
          return Text(
            lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      body: user == null
          ? const Center(child: Text('Please log in to see your groups.'))
          : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('groups')
            .where('members', arrayContains: user.uid)
            .orderBy('lastMessageTimestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('You are not in any group.'));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final group = snapshot.data!.docs[index];
              final groupData = group.data() as Map<String, dynamic>;
              final groupName = groupData['groupName'] as String? ?? 'Unnamed Group';
              final initial = groupName.isNotEmpty ? groupName[0].toUpperCase() : '?';
              final lastMessageTimestamp = groupData['lastMessageTimestamp'] as Timestamp?;
              final lastMessageSenderId = groupData['lastMessageSenderId'] as String?;
              final isLastMessageFromMe = lastMessageSenderId == user.uid;
              final time = lastMessageTimestamp != null
                  ? timeago.format(lastMessageTimestamp.toDate(), locale: 'en_short')
                  : '';

              return ListTile(
                tileColor: !isLastMessageFromMe ? Colors.blue.withOpacity(0.1) : null,
                leading: CircleAvatar(
                  backgroundColor: getAvatarColor(initial),
                  child: Text(initial, style: const TextStyle(color: Colors.white)),
                ),
                title: Row(
                  children: [
                    Text(
                      groupName,
                      style: TextStyle(
                        fontWeight: !isLastMessageFromMe ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      time,
                      style: TextStyle(
                        color: !isLastMessageFromMe ? Colors.blue : Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: !isLastMessageFromMe ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                subtitle: _buildGroupSubtitle(groupData, isLastMessageFromMe),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupChatScreen(
                        groupId: group.id,
                        groupName: groupName,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateGroupDialog,
        backgroundColor: const Color(0xFF1E88E5),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
