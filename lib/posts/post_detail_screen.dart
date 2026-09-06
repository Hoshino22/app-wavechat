import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wavechat/posts/comment_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:wavechat/utils/color_helper.dart';

// Copied from home_screen.dart for show more/less functionality
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
    const int maxLines = 5;
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
              SelectableText( // Allows copying text
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


class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({Key? key, required this.postId}) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {

  // Copied from home_screen.dart to handle liking a post
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>( // Use StreamBuilder for real-time updates
        stream: FirebaseFirestore.instance.collection('posts').doc(widget.postId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Post not found.'));
          }

          final post = snapshot.data!;
          return SingleChildScrollView(
            child: _buildPostItem(context, post),
          );
        },
      ),
    );
  }

  Widget _buildPostItem(BuildContext context, DocumentSnapshot post) {
    final postData = post.data() as Map<String, dynamic>;
    final postTime = (postData['timestamp'] as Timestamp).toDate();
    final likes = postData['likes'] as List<dynamic>? ?? [];
    final commentCount = postData['commentCount'] ?? 0;
    final authorName = postData['authorName'] ?? 'Anonymous';
    final initial = authorName.isNotEmpty ? authorName[0].toUpperCase() : '';
    final authorId = postData['authorId'] as String;

    final currentUser = FirebaseAuth.instance.currentUser;
    final isLiked = currentUser != null && likes.contains(currentUser.uid);


    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 0, 
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
                  backgroundColor: getAvatarColor(initial), // Use avatar color helper
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
              ],
            ),
            const SizedBox(height: 12),
            _ExpandableText(text: postData['text'] ?? ''), // Use expandable text
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
