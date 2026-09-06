import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wavechat/chats/list_chats_screen.dart';
import 'package:wavechat/home/activity_screen.dart';
import 'package:wavechat/home/profile_screen.dart';
import 'package:wavechat/home/search_screen.dart';
import 'package:wavechat/posts/comment_screen.dart';
import 'package:wavechat/posts/post_screen.dart';
import 'package:wavechat/home/settings_screen.dart';
import 'package:wavechat/home/account_info_screen.dart';
import 'package:wavechat/home/friends_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:wavechat/utils/color_helper.dart';
import 'package:wavechat/utils/ui_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
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

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int _selectedIndex = 0;
  final _postTextController = TextEditingController();
  DateTime? backButtonPressTime;
  StreamSubscription? _chatSubscription;
  bool _hasUnreadMessages = false;

  static const List<String> _titles = <String>[
    'Wave Chat',
    'Friends',
    'Create Post',
    'Messenger',
    'Profile'
  ];

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _listenForUnreadMessages();
    timeago.setLocaleMessages('en', timeago.EnMessages());
    timeago.setLocaleMessages('en_short', timeago.EnShortMessages());
  }

  @override
  void dispose() {
    _postTextController.dispose();
    _chatSubscription?.cancel();
    super.dispose();
  }

  void _listenForUnreadMessages() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUser.uid)
        .where('lastMessageRead', isEqualTo: false)
        .where('lastMessageSenderId', isNotEqualTo: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _hasUnreadMessages = snapshot.docs.isNotEmpty;
        });
      }
    });
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (mounted) {
          setState(() {
            _userData = doc.data();
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

  void _onItemTapped(int index) async {
    if (index == 2) {
      // Special handling for create post button
      setState(() {
        _selectedIndex = 2;
      });
    } else if (_selectedIndex == 2 && _postTextController.text.isNotEmpty) {
      final bool? discard = await _showDiscardPostDialog();
      if (discard == true) {
        setState(() {
          _postTextController.clear();
          _selectedIndex = index;
        });
      }
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Future<bool?> _showDiscardPostDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard post?'),
        content: const Text('If you leave now, you will lose your post.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep writing'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
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
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfileScreen(userId: authorId, userName: authorName),
                        ),
                      );
                    },
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

  @override
  Widget build(BuildContext context) {
    String initial = '';
    String userName = 'Loading...';
    final currentUser = FirebaseAuth.instance.currentUser;

    if (!_isLoading && _userData != null) {
      userName = _userData!['fullName'] ?? 'No Name';
      if (userName.isNotEmpty && userName != 'Loading...') {
        initial = userName[0].toUpperCase();
      }
    }

    final List<Widget> widgetOptions = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text(
              "New Post",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No posts yet.'));
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
      const FriendsScreen(),
      PostScreen(
        textController: _postTextController,
        onPostSuccess: () {
          _postTextController.clear();
          setState(() {
            _selectedIndex = 0;
          });
          if (mounted) {
            showStyledSnackBar(context, 'Post added successfully!');
          }
        },
      ),
      const ListChatsScreen(),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text(
              "My Posts",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .where('authorId', isEqualTo: currentUser?.uid)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('You have not created any posts.'));
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
    ];

    return WillPopScope(
       onWillPop: () async {
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return false;
        }
        final now = DateTime.now();
        final shouldPop = backButtonPressTime == null || now.difference(backButtonPressTime!) > const Duration(seconds: 2);
        if (shouldPop) {
          backButtonPressTime = now;
          showStyledSnackBar(context, 'Press back again to exit', duration: const Duration(seconds: 2));
          return false;
        }
        SystemNavigator.pop();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            _titles.elementAt(_selectedIndex),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          actions: [
            if (_selectedIndex == 0)
              IconButton(
                icon: StreamBuilder<QuerySnapshot>(
                  stream: currentUser != null
                      ? FirebaseFirestore.instance
                          .collection('friend_requests')
                          .doc(currentUser.uid)
                          .collection('pending_requests')
                          .snapshots()
                      : const Stream.empty(),
                  builder: (context, requestSnapshot) {
                    final requestCount = requestSnapshot.hasData ? requestSnapshot.data!.docs.length : 0;

                    return StreamBuilder<QuerySnapshot>(
                      stream: currentUser != null
                          ? FirebaseFirestore.instance
                              .collection('notifications')
                              .where('recipientId', isEqualTo: currentUser.uid)
                              .where('isRead', isEqualTo: false)
                              .snapshots()
                          : const Stream.empty(),
                      builder: (context, notificationSnapshot) {
                        final notificationCount = notificationSnapshot.hasData ? notificationSnapshot.data!.docs.length : 0;
                        final totalCount = requestCount + notificationCount;

                        return Stack(
                          children: [
                            const Icon(Icons.notifications_none, color: Colors.white),
                            if (totalCount > 0)
                              Positioned(
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  child: Text(
                                    '$totalCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ActivityScreen()),
                  );
                },
              ),
            if (_selectedIndex == 1)
              IconButton(
                icon: const Icon(Icons.person_add_alt_1_outlined, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Find People'),
                          backgroundColor: const Color(0xFF1E88E5),
                          foregroundColor: Colors.white,
                        ),
                        body: const SearchScreen(),
                      ),
                    ),
                  );
                },
              ),
          ],
          leading: _selectedIndex == 4
              ? Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                )
              : null,
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF1E88E5),
        ),
        drawer: _selectedIndex == 4
            ? Drawer(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: DrawerHeader(
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E88E5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.white,
                              child: _isLoading
                                  ? const CircularProgressIndicator()
                                  : Text(
                                      initial,
                                      style: const TextStyle(
                                          fontSize: 40.0,
                                          color: Color(0xFF1E88E5),
                                          fontWeight: FontWeight.bold),
                                    ),
                            ),
                            const Spacer(),
                             Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  userName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StreamBuilder<QuerySnapshot>(
                                  stream: currentUser != null ? FirebaseFirestore.instance.collection('users').doc(currentUser.uid).collection('friends').snapshots() : const Stream.empty(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) return const SizedBox.shrink();
                                    return Text(
                                      '${snapshot.data!.docs.length} friends',
                                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                                    );
                                  }
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Account Info'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const AccountInfoScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.pop(context); // Close the drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const SettingsScreen()),
                        );
                      },
                    ),
                  ],
                ),
              )
            : null,
        body: Center(
          child: widgetOptions.elementAt(_selectedIndex),
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
            items: <BottomNavigationBarItem>[
              const BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: '',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                label: '',
              ),
              BottomNavigationBarItem(
                label: '',
                icon: Container(
                  width: 48,
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add, color: Colors.grey),
                ),
                activeIcon: Container(
                  width: 48,
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF1E88E5), width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add, color: Color(0xFF1E88E5)),
                ),
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.message_outlined),
                label: '',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                label: '',
              ),
            ],
            currentIndex: _selectedIndex,
            selectedItemColor: const Color(0xFF1E88E5),
            unselectedItemColor: Colors.grey,
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: false,
            showUnselectedLabels: false,
          ),
        ),
      ),
    );
  }
}
