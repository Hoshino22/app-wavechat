import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wavechat/utils/color_helper.dart';
import 'package:wavechat/utils/ui_helper.dart';

class AddMembersScreen extends StatefulWidget {
  final String groupId;
  final List<String> currentMembers;

  const AddMembersScreen({
    Key? key,
    required this.groupId,
    required this.currentMembers,
  }) : super(key: key);

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  final _auth = FirebaseAuth.instance;
  final Set<String> _invitedMembers = {};
  bool _isLoadingInvites = true;

  @override
  void initState() {
    super.initState();
    _fetchExistingInvites();
  }

  Future<void> _fetchExistingInvites() async {
    setState(() {
      _isLoadingInvites = true;
    });
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('groupId', isEqualTo: widget.groupId)
          .where('type', isEqualTo: 'GROUP_INVITE')
          .get();

      final invitedIds = snapshot.docs
          .map((doc) => doc.data()['recipientId'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toSet();

      if (mounted) {
        setState(() {
          _invitedMembers.addAll(invitedIds);
        });
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Failed to load invitation status: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInvites = false;
        });
      }
    }
  }

  Future<void> _sendInvitation(String friendId, String friendName) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    setState(() {
      _invitedMembers.add(friendId);
    });

    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      final inviterName = userDoc.data()?['fullName'] ?? 'Someone';

      final groupDoc =
          await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
      final groupName = groupDoc.data()?['groupName'] ?? 'a group';

      await FirebaseFirestore.instance.collection('notifications').add({
        'recipientId': friendId,
        'senderId': currentUser.uid,
        'senderName': inviterName,
        'type': 'GROUP_INVITE',
        'groupId': widget.groupId,
        'groupName': groupName,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        showStyledSnackBar(context, 'Invitation sent to $friendName.');
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Failed to send invitation: $e', isError: true);
        setState(() {
          _invitedMembers.remove(friendId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Please log in.')));
    }
    if (_isLoadingInvites) {
      return Scaffold(
        appBar: AppBar(
            title: const Text('Invite Members'),
            backgroundColor: const Color(0xFF1E88E5),
            foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite Members'),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('friends')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('You have no friends to invite.'));
          }

          final friendDocs = snapshot.data!.docs;
          final nonMemberFriendIds = friendDocs
              .map((doc) => doc.id)
              .where((id) => !widget.currentMembers.contains(id))
              .toList();

          if (nonMemberFriendIds.isEmpty) {
            return const Center(
                child: Text('All your friends are already in the group.'));
          }

          return FutureBuilder<List<DocumentSnapshot>>(
              future: Future.wait(nonMemberFriendIds.map(
                  (id) => FirebaseFirestore.instance.collection('users').doc(id).get())),
              builder: (context, usersSnapshot) {
                if (usersSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!usersSnapshot.hasData || usersSnapshot.data == null) {
                   return const Center(child: Text('Could not load user data.'));
                }
                final userDocs = usersSnapshot.data!;

                return ListView.builder(
                    itemCount: userDocs.length,
                    itemBuilder: (context, index) {
                      final userDoc = userDocs[index];
                       if (!userDoc.exists) return const SizedBox.shrink();

                      final userData = userDoc.data() as Map<String, dynamic>;
                      final friendId = userDoc.id;
                      final userName =
                          userData['fullName'] as String? ?? 'Unknown User';
                      final isInvited = _invitedMembers.contains(friendId);

                      return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: getAvatarColor(userName.isNotEmpty ? userName[0] : ''),
                            foregroundColor: Colors.white,
                            child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : ''),
                          ),
                          title: Text(userName),
                          trailing: ElevatedButton(
                            onPressed: isInvited
                                ? null
                                : () => _sendInvitation(friendId, userName),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isInvited ? Colors.grey : Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(isInvited ? 'Invited' : 'Invite'),
                          ));
                    });
              });
        },
      ),
    );
  }
}
