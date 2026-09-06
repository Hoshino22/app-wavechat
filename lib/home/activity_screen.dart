import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wavechat/chats/chat_screen.dart';
import 'package:wavechat/chats/group_chat_screen.dart';
import 'package:wavechat/posts/post_detail_screen.dart';
import 'package:wavechat/utils/color_helper.dart';
import 'package:wavechat/utils/ui_helper.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({Key? key}) : super(key: key);

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser;
  final Set<String> _processingRequests = {};

  StreamController<List<DocumentSnapshot>>? _combinedStreamController;
  List<DocumentSnapshot> _requests = [];
  List<DocumentSnapshot> _notifications = [];
  StreamSubscription? _requestsSubscription;
  StreamSubscription? _notificationsSubscription;

  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _combinedStreamController = StreamController<List<DocumentSnapshot>>.broadcast();
      _listenToStreams();
      _markNotificationsAsRead();
    }
  }
  
  Future<void> _markNotificationsAsRead() async {
    if (_currentUser == null) return;

    final notificationsSnapshot = await FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientId', isEqualTo: _currentUser!.uid)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in notificationsSnapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    _notificationsSubscription?.cancel();
    _combinedStreamController?.close();
    super.dispose();
  }

  Timestamp? _getTimestamp(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    if (data.containsKey('timestamp') && data['timestamp'] is Timestamp) return data['timestamp'] as Timestamp;
    if (data.containsKey('createdAt') && data['createdAt'] is Timestamp) return data['createdAt'] as Timestamp;
    return null;
  }

  void _listenToStreams() {
    final requestsStream = FirebaseFirestore.instance.collection('friend_requests').doc(_currentUser!.uid).collection('pending_requests').snapshots();
    _requestsSubscription = requestsStream.listen((snapshot) {
      _requests = snapshot.docs;
      _combineAndSortData();
    });

    final notificationsStream = FirebaseFirestore.instance.collection('notifications').where('recipientId', isEqualTo: _currentUser!.uid).snapshots();
    _notificationsSubscription = notificationsStream.listen((snapshot) {
      _notifications = snapshot.docs;
      _combineAndSortData();
    });
  }

  void _combineAndSortData() {
    final combined = <DocumentSnapshot>[..._requests, ..._notifications];
    combined.sort((a, b) {
      final Timestamp? tsA = _getTimestamp(a);
      final Timestamp? tsB = _getTimestamp(b);
      if (tsA == null && tsB == null) return 0;
      if (tsA == null) return 1;
      if (tsB == null) return -1;
      return tsB.compareTo(tsA);
    });

    if (!(_combinedStreamController?.isClosed ?? true)) {
      _combinedStreamController!.add(combined);
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final difference = DateTime.now().difference(timestamp.toDate());
    if (difference.inDays >= 1) return '${difference.inDays}d ago';
    if (difference.inHours >= 1) return '${difference.inHours}h ago';
    if (difference.inMinutes >= 1) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  Future<void> _handleFriendRequest(String senderId, String senderName, bool accepted) async {
    if (_currentUser == null || _processingRequests.contains(senderId)) return;
    setState(() => _processingRequests.add(senderId));

    try {
      final currentUserId = _currentUser!.uid;
      final currentUserDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserId).get();
      final currentUserName = currentUserDoc.data()?['fullName'] ?? 'Someone';
      
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(FirebaseFirestore.instance.collection('friend_requests').doc(currentUserId).collection('pending_requests').doc(senderId));
      batch.delete(FirebaseFirestore.instance.collection('friend_requests').doc(senderId).collection('sent_requests').doc(currentUserId));

      if (accepted) {
        batch.set(FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('friends').doc(senderId), {'createdAt': FieldValue.serverTimestamp()});
        batch.set(FirebaseFirestore.instance.collection('users').doc(senderId).collection('friends').doc(currentUserId), {'createdAt': FieldValue.serverTimestamp()});
        batch.set(FirebaseFirestore.instance.collection('notifications').doc(), {
          'recipientId': senderId, 'senderName': currentUserName, 'type': 'FRIEND_REQUEST_ACCEPTED', 'isRead': false, 'timestamp': FieldValue.serverTimestamp(),
        });
        if (mounted) showStyledSnackBar(context, 'You are now friends with $senderName!');
      } else {
        batch.set(FirebaseFirestore.instance.collection('notifications').doc(), {
          'recipientId': senderId, 'senderName': currentUserName, 'type': 'FRIEND_REQUEST_DECLINED', 'isRead': false, 'timestamp': FieldValue.serverTimestamp(),
        });
        if (mounted) showStyledSnackBar(context, 'Declined friend request from $senderName.', isError: true);
      }
      await batch.commit();
    } catch (e) {
      if (mounted) showStyledSnackBar(context, 'An error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _processingRequests.remove(senderId));
    }
  }

  Future<void> _handleGroupInvite(String notificationId, String groupId, String groupName, String senderId, bool accepted) async {
    if (_currentUser == null || _processingRequests.contains(notificationId)) return;
    setState(() => _processingRequests.add(notificationId));

    try {
      if (accepted) {
        final groupDocRef = FirebaseFirestore.instance.collection('groups').doc(groupId);
        final batch = FirebaseFirestore.instance.batch();

        batch.update(groupDocRef, {'members': FieldValue.arrayUnion([_currentUser!.uid])});
        
        final currentUserName = _currentUser!.displayName ?? (await _getUserDetails(_currentUser!.uid)).get('fullName') ?? 'Someone';
        batch.set(FirebaseFirestore.instance.collection('notifications').doc(), {
            'recipientId': senderId,
            'senderName': currentUserName,
            'type': 'GROUP_INVITE_ACCEPTED',
            'groupName': groupName,
            'groupId': groupId,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
        });
        
        batch.delete(FirebaseFirestore.instance.collection('notifications').doc(notificationId));
        
        await batch.commit();

        if (mounted) showStyledSnackBar(context, 'You have joined the group $groupName.');

      } else {
        final batch = FirebaseFirestore.instance.batch();
        final currentUserName = _currentUser!.displayName ?? (await _getUserDetails(_currentUser!.uid)).get('fullName') ?? 'Someone';

        batch.delete(FirebaseFirestore.instance.collection('notifications').doc(notificationId));
        batch.set(FirebaseFirestore.instance.collection('notifications').doc(), {
            'recipientId': senderId,
            'senderName': currentUserName,
            'type': 'GROUP_INVITE_DECLINED',
            'groupName': groupName,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
        });
        
        await batch.commit();
        if (mounted) showStyledSnackBar(context, 'Declined group invitation.', isError: true);
      }
    } on FirebaseException catch (e) {
      if (accepted && (e.code == 'permission-denied' || e.code == 'not-found')) {
        if (mounted) {
            showStyledSnackBar(context, 'This group no longer exists.', isError: true);
        }
        await FirebaseFirestore.instance.collection('notifications').doc(notificationId).delete();
      } else {
        if (mounted) showStyledSnackBar(context, 'An error occurred: ${e.message}', isError: true);
      }
    } catch (e) {
      if (mounted) showStyledSnackBar(context, 'An unexpected error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _processingRequests.remove(notificationId));
    }
  }


  Future<void> _dismissNotification(String notificationId) async {
    if (_currentUser == null) return;
    try {
      await FirebaseFirestore.instance.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      if (mounted) showStyledSnackBar(context, 'Failed to dismiss notification: $e', isError: true);
    }
  }

  Future<DocumentSnapshot> _getUserDetails(String userId) => FirebaseFirestore.instance.collection('users').doc(userId).get();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      body: _currentUser == null
          ? const Center(child: Text('Please log in to see your activity.'))
          : StreamBuilder<List<DocumentSnapshot>>(
              stream: _combinedStreamController?.stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.data!.isEmpty) return const Center(child: Text('No new activity.'));

                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data![index];
                    final data = doc.data() as Map<String, dynamic>?;

                    if (doc.reference.path.contains('friend_requests')) {
                      return _buildFriendRequestCard(doc);
                    } else if (data?['type'] == 'GROUP_INVITE') {
                      return _buildGroupInviteCard(doc);
                    } else {
                      return _buildNotificationCard(doc);
                    }
                  },
                );
              },
            ),
    );
  }

  Widget _buildFriendRequestCard(DocumentSnapshot request) {
    final senderId = request.id;
    final timestamp = _getTimestamp(request);

    return FutureBuilder<DocumentSnapshot>(
      key: ValueKey(senderId),
      future: _getUserDetails(senderId),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData || userSnapshot.data?.data() == null) return const SizedBox.shrink();
        final userData = userSnapshot.data!.data() as Map<String, dynamic>;
        final userName = userData['fullName'] as String? ?? 'Unknown User';
        final initial = userName.isNotEmpty ? userName[0].toUpperCase() : '';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0), elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor: getAvatarColor(initial),
                    child: Text(initial, style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: RichText(text: TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: [TextSpan(text: userName, style: const TextStyle(fontWeight: FontWeight.bold)), const TextSpan(text: ' sent you a friend request.')]))),
                ]),
                const SizedBox(height: 12),
                _processingRequests.contains(senderId)
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2.0))
                    : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(timestamp != null ? _formatTimestamp(timestamp) : '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const Spacer(),
                        ElevatedButton(onPressed: () => _handleFriendRequest(senderId, userName, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0))), child: const Text('Accept')),
                        const SizedBox(width: 8),
                        ElevatedButton(onPressed: () => _handleFriendRequest(senderId, userName, false), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0))), child: const Text('Decline')),
                      ]),
              ],
            ),
          ),
        );
      },
    );
  }

   Widget _buildGroupInviteCard(DocumentSnapshot doc) {
    final notification = doc.data() as Map<String, dynamic>;
    final senderName = notification['senderName'] as String? ?? 'Someone';
    final groupName = notification['groupName'] as String? ?? 'a group';
    final groupId = notification['groupId'] as String?;
    final senderId = notification['senderId'] as String?;
    final timestamp = _getTimestamp(doc);

    if (groupId == null || senderId == null) {
      return const SizedBox.shrink();
    }

    return Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0), elevation: 2,
        child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Row(children: [
                        const CircleAvatar(child: Icon(Icons.group_add)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: RichText(
                                text: TextSpan(
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    children: [
                                        TextSpan(text: senderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const TextSpan(text: ' invited you to join '),
                                        TextSpan(text: groupName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const TextSpan(text: '.'),
                                    ],
                                ),
                            ),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    _processingRequests.contains(doc.id)
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2.0))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                                Text(timestamp != null ? _formatTimestamp(timestamp) : '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                const Spacer(),
                                ElevatedButton(onPressed: () => _handleGroupInvite(doc.id, groupId, groupName, senderId, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0))), child: const Text('Accept')),
                                const SizedBox(width: 8),
                                ElevatedButton(onPressed: () => _handleGroupInvite(doc.id, groupId, groupName, senderId, false), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0))), child: const Text('Decline')),
                            ],
                        ),
                ],
            ),
        ),
    );
  }


  Widget _buildNotificationCard(DocumentSnapshot doc) {
    final notification = doc.data() as Map<String, dynamic>;
    final type = notification['type'] as String?;
    final senderName = notification['senderName'] as String? ?? 'Someone';
    final postId = notification['postId'] as String?;
    final senderId = notification['senderId'] as String?;
    final groupId = notification['groupId'] as String?;
    final groupName = notification['groupName'] as String? ?? 'the group';

    String titleText, normalText;
    IconData iconData;
    Color iconColor;

    switch (type) {
      case 'FRIEND_REQUEST_ACCEPTED':
        titleText = senderName; normalText = ' accepted your friend request.'; iconData = Icons.check_circle; iconColor = Colors.green; break;
      case 'FRIEND_REQUEST_DECLINED':
        titleText = senderName; normalText = ' declined your friend request.'; iconData = Icons.cancel; iconColor = Colors.red; break;
      case 'NEW_POST':
        titleText = senderName; normalText = ' created a new post.'; iconData = Icons.article; iconColor = Colors.blue; break;
      case 'NEW_MESSAGE':
        titleText = senderName; normalText = ' sent you a message: ${notification['messagePreview']}'; iconData = Icons.message; iconColor = Colors.orange; break;
      case 'NEW_LIKE':
        titleText = senderName; normalText = ' liked your post.'; iconData = Icons.thumb_up; iconColor = Colors.pink; break;
      case 'NEW_COMMENT':
        titleText = senderName; normalText = ' commented on your post.'; iconData = Icons.comment; iconColor = Colors.cyan; break;
      case 'GROUP_INVITE_ACCEPTED':
        titleText = senderName; normalText = ' accepted your invitation to join ${notification['groupName']}.'; iconData = Icons.check_circle; iconColor = Colors.green; break;
      case 'GROUP_INVITE_DECLINED':
        titleText = senderName; normalText = ' declined your invitation to join ${notification['groupName']}.'; iconData = Icons.cancel; iconColor = Colors.red; break;
      case 'GROUP_MESSAGE':
        titleText = '$senderName'; normalText = ' sent a message in the group $groupName: ${notification['body']}'; iconData = Icons.group; iconColor = Colors.purple; break;
      default:
        titleText = 'New notification'; normalText = ''; iconData = Icons.notifications; iconColor = Colors.grey; break;
    }

    final timestamp = _getTimestamp(doc);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      elevation: 2,
      child: InkWell(
        onTap: () async {
          if (type == 'NEW_MESSAGE' && senderId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ChatScreen(friendId: senderId, friendName: senderName),
              ),
            );
          } else if (postId != null) {
            final postDoc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
            if (postDoc.exists) {
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(postId: postId),
                ),
              );
            } else {
              if (mounted) {
                showStyledSnackBar(context, 'This post has been deleted.', isError: true);
              }
            }
          } else if (type == 'GROUP_MESSAGE' || type == 'GROUP_INVITE_ACCEPTED') {
            if (groupId != null) {
              try {
                final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
                if (groupDoc.exists) {
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          GroupChatScreen(groupId: groupId, groupName: groupName),
                    ),
                  );
                } else {
                  if (mounted) {
                    showStyledSnackBar(context, 'This group no longer exists.', isError: true);
                  }
                }
              } on FirebaseException catch (e) {
                if (mounted && (e.code == 'permission-denied' || e.code == 'not-found')) {
                  showStyledSnackBar(context, 'This group no longer exists.', isError: true);
                } else if (mounted) {
                  showStyledSnackBar(context, 'An error occurred: ${e.message}', isError: true);
                }
              } catch (e) {
                if (mounted) {
                  showStyledSnackBar(context, 'An unexpected error occurred: $e', isError: true);
                }
              }
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(backgroundColor: iconColor.withOpacity(0.1), child: Icon(iconData, color: iconColor)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black87),
                        children: [
                          TextSpan(text: titleText, style: const TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: normalText),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timestamp != null ? _formatTimestamp(timestamp) : '',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _dismissNotification(doc.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
