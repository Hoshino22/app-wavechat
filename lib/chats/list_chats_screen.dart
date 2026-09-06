import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wavechat/chats/chat_screen.dart';
import 'package:wavechat/chats/groups_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:wavechat/utils/color_helper.dart';

class ListChatsScreen extends StatefulWidget {
  const ListChatsScreen({super.key});

  @override
  State<ListChatsScreen> createState() => _ListChatsScreenState();
}

class _ListChatsScreenState extends State<ListChatsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    timeago.setLocaleMessages('en', timeago.EnMessages());
    timeago.setLocaleMessages('en_short', timeago.EnShortMessages());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: const Color(0xFF1E88E5),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            indicatorColor: Colors.white,
            overlayColor: MaterialStateProperty.all(Colors.transparent),
            tabs: const [
              Tab(text: 'Chat'),
              Tab(text: 'Groups'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _RecentChatsWidget(),
              GroupsScreen(),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentChatsWidget extends StatelessWidget {
  const _RecentChatsWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Center(child: Text('Please log in to see your chats.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .orderBy('lastMessageTimestamp', descending: true)
          .snapshots(),
      builder: (context, chatSnapshot) {
        if (chatSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (chatSnapshot.hasError) {
          return Center(child: Text('Error: \${chatSnapshot.error}'));
        }
        if (!chatSnapshot.hasData || chatSnapshot.data!.docs.isEmpty) {
          return const Center(child: Text('You have no recent chats.'));
        }

        final chatDocs = chatSnapshot.data!.docs;

        return ListView.builder(
          itemCount: chatDocs.length,
          itemBuilder: (context, index) {
            final chatDoc = chatDocs[index];
            final chatData = chatDoc.data() as Map<String, dynamic>;
            final participants = List<String>.from(chatData['participants'] ?? []);

            if (participants.length < 2) {
              return const SizedBox.shrink();
            }

            final friendId = participants.firstWhere((id) => id != currentUser.uid, orElse: () => '');
            if (friendId.isEmpty) {
              return const SizedBox.shrink();
            }

            final lastMessage = chatData['lastMessage'] as String?;
            final lastMessageSenderId = chatData['lastMessageSenderId'] as String?;
            final lastMessageTimestamp = chatData['lastMessageTimestamp'] as Timestamp?;
            final lastMessageRead = chatData['lastMessageRead'] as bool?;

            final time = lastMessageTimestamp != null
                ? timeago.format(lastMessageTimestamp.toDate(), locale: 'en_short')
                : '';

            final bool isLastMessageFromMe = lastMessageSenderId == currentUser.uid;
            final bool isUnread = lastMessageRead == false && !isLastMessageFromMe;

            String subtitleText;
            if (lastMessage != null && lastMessage.isNotEmpty) {
              subtitleText = isLastMessageFromMe ? 'You: $lastMessage' : lastMessage;
            } else if (lastMessageTimestamp != null) {
              subtitleText = 'Chat started';
            } else {
              subtitleText = 'No messages yet.';
            }

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(friendId).get(),
              builder: (context, userSnapshot) {
                String userName = '...';
                String initial = '?';
                bool isUserDataLoaded = userSnapshot.hasData && userSnapshot.data!.exists;

                if (isUserDataLoaded) {
                  final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                  userName = userData['fullName'] as String? ?? 'Unknown User';
                  initial = userName.isNotEmpty ? userName[0].toUpperCase() : '?';
                }

                return ListTile(
                  tileColor: isUnread ? Colors.blue.withOpacity(0.1) : null,
                  leading: CircleAvatar(
                    backgroundColor: getAvatarColor(initial),
                    child: Text(initial, style: const TextStyle(color: Colors.white)),
                  ),
                  title: Row(
                    children: [
                      Text(
                        userName,
                        style: TextStyle(
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        time,
                        style: TextStyle(
                          color: isUnread ? Colors.blue : Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isLastMessageFromMe ? Colors.grey.shade600 : (isUnread ? Colors.black87 : Colors.grey.shade600),
                      fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    if (isUserDataLoaded) {
                      if (isUnread) {
                        FirebaseFirestore.instance
                            .collection('chats')
                            .doc(chatDoc.id)
                            .update({'lastMessageRead': true});
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            friendId: friendId,
                            friendName: userName,
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
