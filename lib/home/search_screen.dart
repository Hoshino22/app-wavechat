
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wavechat/chats/chat_screen.dart';
import 'package:wavechat/utils/color_helper.dart';
import 'package:wavechat/utils/ui_helper.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = "";
  final _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sendFriendRequest(String recipientId, String recipientName) async {
    if (_currentUser == null) return;

    final senderId = _currentUser!.uid;

    // Add a pending request to the recipient
    await FirebaseFirestore.instance
        .collection('friend_requests')
        .doc(recipientId)
        .collection('pending_requests')
        .doc(senderId)
        .set({
      'from': senderId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Mark the request as sent for the sender
    await FirebaseFirestore.instance
        .collection('friend_requests')
        .doc(senderId)
        .collection('sent_requests')
        .doc(recipientId)
        .set({
      'to': recipientId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      showStyledSnackBar(context, 'Friend request sent to $recipientName!');
    }

    setState(() {}); // Refresh UI to show 'Request Sent'
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _searchQuery.isEmpty
                  ? const Stream.empty() // Show nothing if search is empty
                  : FirebaseFirestore.instance
                      .collection('users')
                      .where('fullName', isGreaterThanOrEqualTo: _searchQuery)
                      .where('fullName', isLessThanOrEqualTo: _searchQuery + '\uf8ff')
                      .snapshots(),
              builder: (context, snapshot) {
                if (_searchQuery.isEmpty) {
                  return const Center(child: Text('Enter a name to search.'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No users found.'));
                }

                final users = snapshot.data!.docs
                    .where((doc) => doc.id != _currentUser?.uid)
                    .toList();

                if (users.isEmpty) {
                  return const Center(child: Text('No other users found.'));
                }

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final userDoc = users[index];
                    final userData = userDoc.data() as Map<String, dynamic>;
                    final userName = userData['fullName'] ?? 'No Name';
                    final userEmail = userData['email'] ?? 'No Email';
                    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : '';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: getAvatarColor(initial),
                        child: Text(initial, style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(userName),
                      subtitle: Text(userEmail),
                      trailing: _buildFriendshipButton(userDoc.id, userName),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
  }

  Widget _buildFriendshipButton(String userId, String userName) {
    if (_currentUser == null) return const SizedBox.shrink();

    final currentUserId = _currentUser!.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('friends').doc(userId).snapshots(),
      builder: (context, friendSnapshot) {
        if (friendSnapshot.connectionState == ConnectionState.waiting) {
          return ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300]),
            child: const Text('...', style: TextStyle(color: Colors.black)),
          );
        }

        if (friendSnapshot.hasData && friendSnapshot.data!.exists) {
          return IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    friendId: userId,
                    friendName: userName,
                  ),
                ),
              );
            },
          );
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('friend_requests').doc(currentUserId).collection('sent_requests').doc(userId).snapshots(),
          builder: (context, requestSnapshot) {
            if (requestSnapshot.connectionState == ConnectionState.waiting) {
              return ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300]),
                child: const Text('...', style: TextStyle(color: Colors.black)),
              );
            }
            if (requestSnapshot.hasData && requestSnapshot.data!.exists) {
              return ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300]),
                child: const Text('Request Sent', style: TextStyle(color: Colors.black)),
              );
            }
            return ElevatedButton(
              onPressed: () => _sendFriendRequest(userId, userName),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('Add Friend'),
            );
          },
        );
      },
    );
  }
}
