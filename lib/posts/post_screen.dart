import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wavechat/utils/ui_helper.dart';

class PostScreen extends StatefulWidget {
  final TextEditingController? textController;
  final VoidCallback? onPostSuccess;

  const PostScreen({Key? key, this.textController, this.onPostSuccess}) : super(key: key);

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  late TextEditingController _postTextController;
  final _auth = FirebaseAuth.instance;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _postTextController = widget.textController ?? TextEditingController();
  }

  Future<void> _addPost() async {
    if (_postTextController.text.trim().isEmpty) {
      return; // Do not post if the text is empty
    }

    setState(() {
      _isPosting = true;
    });

    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Get user's full name from Firestore
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final fullName = userDoc.data()?['fullName'] ?? 'Anonymous';

        // Create the post and get its reference
        final postRef = await FirebaseFirestore.instance.collection('posts').add({
          'text': _postTextController.text,
          'timestamp': Timestamp.now(),
          'authorId': user.uid,
          'authorName': fullName, // Add author's name
          'likes': [], // Initialize likes as an empty list
          'commentCount': 0, // Initialize comment count to 0
        });

        // Notify friends about the new post
        final friendsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('friends')
            .get();

        final batch = FirebaseFirestore.instance.batch();
        
        for (final friendDoc in friendsSnapshot.docs) {
          final friendId = friendDoc.id;
          final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(notificationRef, {
            'recipientId': friendId,
            'senderName': fullName,
            'type': 'NEW_POST',
            'postId': postRef.id, // ID of the new post
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit(); // Commit all notifications at once

        if (mounted) {
          widget.onPostSuccess?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Error adding post: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _postTextController,
                cursorColor: Colors.blue,
                decoration: const InputDecoration(
                  hintText: 'What\'s on your mind?',
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
                maxLines: null, // Allow unlimited lines
                expands: true, // Make TextField expand
              ),
            ),
            const SizedBox(height: 16), // Add some space before the button
            ElevatedButton(
              onPressed: _isPosting ? null : _addPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2979FF),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)
                )
              ),
              child: _isPosting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Post'),
            ),
          ],
        ),
      );
  }
}
