import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wavechat/chats/chat_screen.dart';
import 'package:wavechat/utils/color_helper.dart';
import 'package:wavechat/utils/ui_helper.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _unfriend(String friendId, String friendName) async {
    if (_currentUser == null) return;
    final currentUserId = _currentUser!.uid;

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Remove friend from current user's list
      final currentUserFriendRef = FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('friends').doc(friendId);
      batch.delete(currentUserFriendRef);

      // Remove current user from friend's list
      final friendUserRef = FirebaseFirestore.instance.collection('users').doc(friendId).collection('friends').doc(currentUserId);
      batch.delete(friendUserRef);

      await batch.commit();

      if (mounted) {
        showStyledSnackBar(context, 'You are no longer friends with $friendName.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Failed to unfriend: $e', isError: true);
      }
    }
  }

  Future<DocumentSnapshot> _getUserDetails(String userId) async {
    return FirebaseFirestore.instance.collection('users').doc(userId).get();
  }

  void _showUnfriendConfirmation(BuildContext context, String friendId, String friendName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Unfriend'),
          content: Text('Are you sure you want to unfriend $friendName?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Unfriend', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                _unfriend(friendId, friendName);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(child: Text('Please log in to see your friends.'));
    }

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
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(_currentUser!.uid)
                .collection('friends')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('You have no friends yet.'));
              }

              final friendDocs = snapshot.data!.docs;

              return FutureBuilder<List<DocumentSnapshot>>(
                future: Future.wait(friendDocs.map((doc) => _getUserDetails(doc.id)).toList()),
                builder: (context, usersSnapshot) {
                  if (usersSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (usersSnapshot.hasError) {
                    return Center(child: Text('Error fetching friend details: ${usersSnapshot.error}'));
                  }
                  if (!usersSnapshot.hasData || usersSnapshot.data!.isEmpty) {
                    return const Center(child: Text('You have no friends yet.'));
                  }

                  final filteredFriends = usersSnapshot.data!.where((userDoc) {
                    final userData = userDoc.data() as Map<String, dynamic>;
                    final userName = userData['fullName'] as String? ?? 'Unknown User';
                    return userName.toLowerCase().contains(_searchQuery.toLowerCase());
                  }).toList();

                  if (filteredFriends.isEmpty) {
                    return const Center(child: Text('No friends found.'));
                  }

                  return ListView.builder(
                    itemCount: filteredFriends.length,
                    itemBuilder: (context, index) {
                      final userDoc = filteredFriends[index];
                      final friendId = userDoc.id;
                      final userData = userDoc.data() as Map<String, dynamic>;
                      final userName = userData['fullName'] as String? ?? 'Unknown User';
                      final userEmail = userData['email'] as String? ?? 'No email';
                      final initial = userName.isNotEmpty ? userName[0].toUpperCase() : '';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: getAvatarColor(initial),
                          child: Text(initial, style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(userName),
                        subtitle: Text(userEmail),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                              IconButton(
                                icon: const Icon(Icons.chat),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatScreen(
                                        friendId: friendId,
                                        friendName: userName,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'unfriend') {
                                    _showUnfriendConfirmation(context, friendId, userName);
                                  }
                                },
                                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'unfriend',
                                    child: Text('Unfriend'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
