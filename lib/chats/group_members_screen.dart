import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wavechat/utils/color_helper.dart';

class GroupMembersScreen extends StatefulWidget {
  final String groupId;

  const GroupMembersScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  late Future<(List<dynamic>, String?)> _membersFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = _getGroupMembers();
  }

  Future<(List<dynamic>, String?)> _getGroupMembers() async {
    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
    final members = groupDoc.data()?['members'] as List<dynamic>? ?? [];
    final creatorId = groupDoc.data()?['createdBy'] as String?;
    return (members, creatorId);
  }

  Future<void> _kickMember(String memberId) async {
    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'members': FieldValue.arrayRemove([memberId]),
      });
      // Refresh the list
      setState(() {
        _membersFuture = _getGroupMembers();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to kick member: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showKickConfirmationDialog(String memberId, String memberName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kick Member'),
        content: Text('Are you sure you want to kick $memberName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _kickMember(memberId);
            },
            child: const Text('Kick', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Members'),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<(List<dynamic>, String?)>(
        future: _membersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.$1.isEmpty) {
            return const Center(child: Text('This group has no members.'));
          }

          final memberIds = snapshot.data!.$1;
          final creatorId = snapshot.data!.$2;
          final isCurrentUserAdmin = currentUserId == creatorId;

          return ListView.builder(
            itemCount: memberIds.length,
            itemBuilder: (context, index) {
              final memberId = memberIds[index] as String;
              final isMemberAdmin = memberId == creatorId;

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(memberId).get(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const ListTile(title: Text('Loading...'));
                  }
                  if (!userSnapshot.hasData) {
                    return const ListTile(title: Text('Unknown Member'));
                  }

                  final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                  final userName = userData?['fullName'] ?? 'Unknown User';
                  final initial = userName.isNotEmpty ? userName[0].toUpperCase() : '';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: getAvatarColor(initial),
                      foregroundColor: Colors.white,
                      child: Text(initial),
                    ),
                    title: Text(userName),
                    trailing: isCurrentUserAdmin && !isMemberAdmin
                        ? PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'kick') {
                                _showKickConfirmationDialog(memberId, userName);
                              }
                            },
                            itemBuilder: (BuildContext context) => [
                              const PopupMenuItem<String>(
                                value: 'kick',
                                child: Text('Kick', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          )
                        : isMemberAdmin
                            ? const Text(
                                'Admin',
                                style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                              )
                            : null,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
