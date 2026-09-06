import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:wavechat/posts/comment_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:wavechat/utils/color_helper.dart';
import 'package:wavechat/utils/ui_helper.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const ProfileScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _likePost(String postId, String authorId, List<dynamic> likes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final newLikes = List.from(likes);
      bool isLiked = newLikes.contains(user.uid);

      if (isLiked) {
        newLikes.remove(user.uid);
      } else {
        newLikes.add(user.uid);
        if (user.uid != authorId) {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          final likerName = userDoc.data()?['fullName'] ?? 'Someone';

          FirebaseFirestore.instance.collection('notifications').add({
            'recipientId': authorId,
            'senderName': likerName,
            'type': 'NEW_LIKE',
            'postId': postId,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      }
      await FirebaseFirestore.instance.collection('posts').doc(postId).update({'likes': newLikes});
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      await FirebaseFirestore.instance.collection('posts').doc(postId).delete();
      if (mounted) {
        showStyledSnackBar(context, 'Post deleted successfully!');
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Error deleting post: $e', isError: true);
      }
    }
  }

  Future<void> _showDeleteConfirmationDialog(String postId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Post'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to delete this post?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () {
                _deletePost(postId);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text(
              "Posts by ${widget.userName}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .where('authorId', isEqualTo: widget.userId)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('This user has no posts.'));
                }
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final post = snapshot.data!.docs[index];
                    return _buildPostItem(post, currentUser?.uid);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostItem(DocumentSnapshot post, String? currentUserId) {
    final postData = post.data() as Map<String, dynamic>;
    final postTime = (postData['timestamp'] as Timestamp).toDate();
    final isAuthor = currentUserId == postData['authorId'];
    final likes = postData['likes'] as List<dynamic>? ?? [];
    final isLiked = currentUserId != null && likes.contains(currentUserId);
    final commentCount = postData['commentCount'] ?? 0;
    final authorName = postData['authorName'] ?? 'Anonymous';
    final initial = authorName.isNotEmpty ? authorName[0].toUpperCase() : '';
    final authorId = postData['authorId'] as String;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                   backgroundColor: getAvatarColor(initial),
                  radius: 20,
                  child: Text(initial, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authorName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeago.format(postTime, locale: 'en_short'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (isAuthor)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _showDeleteConfirmationDialog(post.id);
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ExpandableText(text: postData['text'] ?? ''),
            const SizedBox(height: 8),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                        color: isLiked ? Colors.blue : Colors.grey,
                        size: 20,
                      ),
                      onPressed: () => _likePost(post.id, authorId, likes),
                    ),
                    Text(
                      '${likes.length}',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.comment_outlined, color: Colors.grey, size: 20),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CommentScreen(postId: post.id),
                          ),
                        );
                      },
                    ),
                    Text(
                      '$commentCount',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _ExpandableText extends StatefulWidget {
  final String text;

  const _ExpandableText({
    Key? key,
    required this.text,
  }) : super(key: key);

  @override
  _ExpandableTextState createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    const int maxLines = 3;
    const int maxChars = 100;

    final text = widget.text;

    final isLongText = text.length > maxChars;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(text: text, style: const TextStyle(fontSize: 14, height: 1.4));
        final textPainter = TextPainter(text: textSpan, maxLines: maxLines, textDirection: TextDirection.ltr);
        textPainter.layout(maxWidth: constraints.maxWidth);

        final needsTruncation = textPainter.didExceedMaxLines || isLongText;

        if (needsTruncation && !_isExpanded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              GestureDetector(
                onTap: () => setState(() => _isExpanded = true),
                child: Text(
                  ' Show more',
                  style: TextStyle(color: Colors.blue[500]),
                ),
              ),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                text,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              if (needsTruncation && _isExpanded)
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = false),
                  child: Text(
                    'Show less',
                     style: TextStyle(color: Colors.blue[500]),
                  ),
                ),
            ],
          );
        }
      },
    );
  }
}
