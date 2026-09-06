import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:wavechat/utils/color_helper.dart';

// Widget for expandable text, copied from another screen
class _ExpandableText extends StatefulWidget {
  final String text;

  const _ExpandableText({Key? key, required this.text}) : super(key: key);

  @override
  _ExpandableTextState createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    const int maxLines = 5; // You can adjust this value
    const int maxChars = 100; // You can adjust this value

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
                  'Show more',
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

class CommentScreen extends StatefulWidget {
  final String postId;

  const CommentScreen({Key? key, required this.postId}) : super(key: key);

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final _commentController = TextEditingController();
  final _auth = FirebaseAuth.instance;

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) {
      return;
    }

    final user = _auth.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final fullName = userDoc.data()?['fullName'] ?? 'Anonymous';

      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final postSnapshot = await transaction.get(postRef);
        if (!postSnapshot.exists) {
          throw Exception("Post does not exist!");
        }

        final postData = postSnapshot.data()!;
        final authorId = postData['authorId'];

        // Increment comment count
        final newCommentCount = (postData['commentCount'] ?? 0) + 1;
        transaction.update(postRef, {'commentCount': newCommentCount});

        // Add the comment
        final newCommentRef = postRef.collection('comments').doc();
        transaction.set(newCommentRef, {
          'text': _commentController.text,
          'authorName': fullName,
          'authorId': user.uid,
          'timestamp': Timestamp.now(),
        });

        // Create notification for the post author
        if (user.uid != authorId) {
          final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
          transaction.set(notificationRef, {
            'recipientId': authorId,
            'senderName': fullName,
            'type': 'NEW_COMMENT',
            'postId': widget.postId,
            'commentText': _commentController.text.length > 50 ? '${_commentController.text.substring(0, 50)}...' : _commentController.text,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      });

      _commentController.clear();
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
      final commentRef = postRef.collection('comments').doc(commentId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final postSnapshot = await transaction.get(postRef);
        if (!postSnapshot.exists) {
          throw Exception("Post does not exist!");
        }

        final newCommentCount = (postSnapshot.data()!['commentCount'] ?? 1) - 1;

        transaction.update(postRef, {'commentCount': newCommentCount});
        transaction.delete(commentRef);
      });
    }
  }

  Widget _buildCommentItem(Map<String, dynamic> commentData, String commentId) {
    final commentTime = (commentData['timestamp'] as Timestamp).toDate();
    final authorName = commentData['authorName'] ?? 'Anonymous';
    final initial = authorName.isNotEmpty ? authorName[0].toUpperCase() : '';
    final isAuthor = _auth.currentUser?.uid == commentData['authorId'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: getAvatarColor(initial),
            radius: 20,
            child: Text(initial, style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      authorName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeago.format(commentTime, locale: 'en_short'),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _ExpandableText(text: commentData['text'] ?? ''),
              ],
            ),
          ),
          if (isAuthor)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteComment(commentId);
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comments'),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(widget.postId)
                  .collection('comments')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No comments yet.'));
                }
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final comment = snapshot.data!.docs[index];
                    final commentData = comment.data() as Map<String, dynamic>;
                    final commentId = comment.id;
                    return _buildCommentItem(commentData, commentId);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
