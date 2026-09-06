import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:wavechat/utils/ui_helper.dart';

class ChatScreen extends StatefulWidget {
  final String friendId;
  final String friendName;

  const ChatScreen({Key? key, required this.friendId, required this.friendName})
      : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late final String _chatRoomId;
  OverlayEntry? _unsendOverlay;
  late Stream<DocumentSnapshot> _friendshipStream;

  // Pagination and real-time state
  final _scrollController = ScrollController();
  List<DocumentSnapshot> _messages = [];
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  StreamSubscription? _messageStreamSubscription;
  static const int _messagesLimit = 20;
  bool _showScrollToBottomButton = false;


  @override
  void initState() {
    super.initState();
    final currentUserId = _auth.currentUser!.uid;
    _chatRoomId = _getChatRoomId(currentUserId, widget.friendId);
    _friendshipStream = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('friends')
        .doc(widget.friendId)
        .snapshots();

    _markAsRead();

    // CORRECTLY ensure the chat room document exists before fetching messages.
    Future.microtask(() async {
      bool success = await _createChatRoomIfNeeded();
      if(success && mounted) {
        _fetchInitialMessages();
      }
    });

    _scrollController.addListener(_scrollListener);
  }
  
  Future<void> _markAsRead() async {
    final chatRef = _firestore.collection('chats').doc(_chatRoomId);
    await chatRef.set({
      'lastMessageRead': true,
    }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _messageStreamSubscription?.cancel();
    _hideUnsendOverlay();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchMoreMessages();
    }
    if (_scrollController.position.pixels > MediaQuery.of(context).size.height) {
      if (!_showScrollToBottomButton) {
        setState(() {
          _showScrollToBottomButton = true;
        });
      }
    } else {
      if (_showScrollToBottomButton) {
        setState(() {
          _showScrollToBottomButton = false;
        });
      }
    }
  }

  String _getChatRoomId(String a, String b) {
    return a.hashCode <= b.hashCode ? '$a\_$b' : '$b\_$a';
  }

  // CORRECTED IMPLEMENTATION
  Future<bool> _createChatRoomIfNeeded() async {
    final chatRef = _firestore.collection('chats').doc(_chatRoomId);
    try {
      // Use set with merge:true. This will create the document if it doesn't exist,
      // or do nothing if it already exists but ensures the participants are there.
      // This is safe, idempotent, and crucial for the security rules to pass.
      await chatRef.set(
        {
          'participants': [_auth.currentUser!.uid, widget.friendId],
        },
        SetOptions(merge: true),
      );
      return true;
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Error initializing chat: $e', isError: true);
        setState(() => _isLoadingInitial = false);
      }
      return false;
    }
  }


 Future<void> _fetchInitialMessages() async {
    if (!mounted) return;
    setState(() {
      _isLoadingInitial = true;
    });

    try {
      final query = _firestore
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(_messagesLimit);

      final snapshot = await query.get();

      if (mounted) {
        setState(() {
          _messages = snapshot.docs;
          if (snapshot.docs.isNotEmpty) {
            _lastDocument = snapshot.docs.last;
          }
          _hasMore = snapshot.docs.length == _messagesLimit;
          _isLoadingInitial = false;
        });
        // After initial fetch, listen for new messages
        _listenForNewMessages();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
        });
        showStyledSnackBar(context, 'Error loading messages: $e', isError: true);
      }
    }
  }

  Future<void> _fetchMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _lastDocument == null) return;
    if (!mounted) return;
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final query = _firestore
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_messagesLimit);

      final snapshot = await query.get();

      if (mounted) {
        setState(() {
          _messages.addAll(snapshot.docs);
          if (snapshot.docs.isNotEmpty) {
            _lastDocument = snapshot.docs.last;
          }
          _hasMore = snapshot.docs.length == _messagesLimit;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        showStyledSnackBar(context, 'Error loading more messages: $e', isError: true);
      }
    }
  }

  void _listenForNewMessages() {
    _messageStreamSubscription?.cancel();
    final query = _firestore
        .collection('chats')
        .doc(_chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1);

    _messageStreamSubscription = query.snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final newMessage = snapshot.docs.first;
        if (mounted && _messages.every((msg) => msg.id != newMessage.id)) {
          setState(() {
            _messages.insert(0, newMessage);
          });
        }
      }
    });
  }


  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
        final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        final senderName = userDoc.data()?['fullName'] ?? 'Someone';

        final chatRef = _firestore.collection('chats').doc(_chatRoomId);
        final messageRef = chatRef.collection('messages').doc();

        await _firestore.runTransaction((transaction) async {
            final chatDoc = await transaction.get(chatRef);

            if (!chatDoc.exists) {
                transaction.set(chatRef, {
                    'participants': [currentUser.uid, widget.friendId],
                    'lastMessage': messageText,
                    'lastMessageTimestamp': FieldValue.serverTimestamp(),
                    'lastMessageSenderId': currentUser.uid,
                    'lastMessageRead': false,
                });
            } else {
                transaction.update(chatRef, {
                    'lastMessage': messageText,
                    'lastMessageTimestamp': FieldValue.serverTimestamp(),
                    'lastMessageSenderId': currentUser.uid,
                    'lastMessageRead': false,
                });
            }

            transaction.set(messageRef, {
                'text': messageText,
                'senderId': currentUser.uid,
                'senderName': senderName,
                'timestamp': FieldValue.serverTimestamp(),
            });
        });


        final notificationRef = _firestore.collection('notifications').doc();
        await notificationRef.set({
            'recipientId': widget.friendId,
            'senderId': currentUser.uid,
            'senderName': senderName,
            'type': 'NEW_MESSAGE',
            'messagePreview': messageText.length > 30 ? '${messageText.substring(0, 30)}...' : messageText,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
        });

    } catch (e) {
        if (mounted) {
            showStyledSnackBar(context, 'Error sending message: $e', isError: true);
        }
    }
}




  Future<void> _unsendMessage(String messageId) async {
    final chatRef = _firestore.collection('chats').doc(_chatRoomId);
    final messageRef = chatRef.collection('messages').doc(messageId);

    // Optimistically remove from UI
    setState(() {
      _messages.removeWhere((msg) => msg.id == messageId);
    });

    try {
      // 1. Delete the message
      await messageRef.delete();

      // 2. Query for the new last message
      final lastMessageSnapshot = await chatRef
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      // 3. Update the parent chat document
      if (lastMessageSnapshot.docs.isNotEmpty) {
        final lastMessage = lastMessageSnapshot.docs.first.data();
        await chatRef.update({
          'lastMessage': lastMessage['text'],
          'lastMessageSenderId': lastMessage['senderId'],
          'lastMessageTimestamp': lastMessage['timestamp'],
        });
      } else {
        // No messages left, delete the last message fields
        await chatRef.update({
          'lastMessage': FieldValue.delete(),
          'lastMessageSenderId': FieldValue.delete(),
          'lastMessageTimestamp': FieldValue.delete(),
        });
      }
    } catch (e) {
       if (mounted) {
        showStyledSnackBar(context, 'Failed to unsend message: $e', isError: true);
      }
    }
  }

  void _showUnsendOverlay(
      BuildContext itemContext, String messageId) {
    _hideUnsendOverlay(); 
    final renderBox = itemContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final newOverlay = OverlayEntry(
      builder: (context) {
        final offset = renderBox.localToGlobal(Offset.zero);
        return Positioned(
          top: offset.dy - 25,
          right: 8.0,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 5)
                ],
              ),
              child: InkWell(
                onTap: () {
                  _unsendMessage(messageId);
                  _hideUnsendOverlay();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.undo, size: 18),
                    const SizedBox(width: 8),
                    const Text('Unsend', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(itemContext).insert(newOverlay);
    setState(() {
       _unsendOverlay = newOverlay;
    });
  }

  void _hideUnsendOverlay() {
    if (_unsendOverlay != null) {
      _unsendOverlay!.remove();
       setState(() {
        _unsendOverlay = null;
      });
    }
  }

  Widget _buildMessageItem(Map<String, dynamic> messageData, String messageId,
      {bool showTimestamp = false, String formattedTimestamp = '', bool showTimeBelow = false}) {
    final isMe = messageData['senderId'] == _auth.currentUser?.uid;
    final timestamp = messageData['timestamp'] as Timestamp?;

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showTimestamp)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                formattedTimestamp,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        Builder(
          builder: (itemContext) { 
            return GestureDetector(
              onLongPress: () {
                if (isMe) {
                  _showUnsendOverlay(itemContext, messageId);
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  mainAxisAlignment:
                      isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 2 / 3),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 16),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue[200] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          messageData['text'] ?? '',
                          style: const TextStyle(fontSize: 16.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (showTimeBelow)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12, left: 12, bottom: 8),
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                timestamp != null ? DateFormat.jm().format(timestamp.toDate()) : '',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageComposer() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _friendshipStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink(); // Show nothing while checking
        }

        final areFriends = snapshot.hasData && snapshot.data!.exists;

        if (areFriends) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 15, horizontal: 15),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          );
        } else {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            color: Colors.grey[200],
            child: Text(
              'You are no longer friends with ${widget.friendName}. Add them as a friend to send messages.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _unsendOverlay == null,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _hideUnsendOverlay();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.friendName),
          backgroundColor: const Color(0xFF1E88E5),
          foregroundColor: Colors.white,
        ),
        body: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            _hideUnsendOverlay();
          },
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: _isLoadingInitial
                        ? const Center(child: CircularProgressIndicator())
                        : _messages.isEmpty
                            ? const Center(child: Text('No messages yet. Send one to start!'))
                            : ListView.builder(
                                controller: _scrollController,
                                reverse: true,
                                itemCount: _messages.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _messages.length) {
                                    return _isLoadingMore
                                        ? const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 16.0),
                                            child: Center(child: CircularProgressIndicator()),
                                          )
                                        : const SizedBox.shrink();
                                  }

                                  final message = _messages[index];
                                  final messageData = message.data() as Map<String, dynamic>;
                                  final messageId = message.id;

                                  final currentTimestampData =
                                      messageData['timestamp'] as Timestamp?;
                                  if (currentTimestampData == null) {
                                    return _buildMessageItem(messageData, messageId);
                                  }
                                  final currentTimestamp = currentTimestampData.toDate();

                                  bool showTimestampForCurrent = false;
                                  String formattedTimestamp = '';

                                  if (index == _messages.length - 1) {
                                    showTimestampForCurrent = true;
                                    formattedTimestamp = DateFormat.yMMMd().add_jm().format(currentTimestamp);
                                  } else {
                                    final previousMessage = _messages[index + 1];
                                    final previousMessageData =
                                        previousMessage.data() as Map<String, dynamic>;
                                    final previousTimestampData =
                                        previousMessageData['timestamp'] as Timestamp?;

                                    if (previousTimestampData != null) {
                                      final previousTimestamp = previousTimestampData.toDate();
                                      final isNewDay =
                                          currentTimestamp.day != previousTimestamp.day ||
                                              currentTimestamp.month != previousTimestamp.month ||
                                              currentTimestamp.year != previousTimestamp.year;

                                      if (isNewDay) {
                                        showTimestampForCurrent = true;
                                        formattedTimestamp = DateFormat.yMMMd().add_jm().format(currentTimestamp);
                                      } else if (currentTimestamp.difference(previousTimestamp).inMinutes >= 20) {
                                        showTimestampForCurrent = true;
                                        formattedTimestamp = DateFormat.jm().format(currentTimestamp);
                                      }
                                    }
                                  }

                                  bool showTimeBelow = false;
                                  final currentSenderId = messageData['senderId'];

                                  if (index == 0) {
                                    showTimeBelow = true;
                                  } else {
                                    final nextMessage = _messages[index - 1];
                                    final nextMessageData = nextMessage.data() as Map<String, dynamic>;
                                    final nextSenderId = nextMessageData['senderId'];
                                    final nextTimestampData = nextMessageData['timestamp'] as Timestamp?;

                                    bool willShowTimestampForNext = false;
                                    if (nextTimestampData != null) {
                                      final nextTimestamp = nextTimestampData.toDate();
                                      final isNewDay = nextTimestamp.day != currentTimestamp.day ||
                                          nextTimestamp.month != currentTimestamp.month ||
                                          nextTimestamp.year != currentTimestamp.year;

                                      if (isNewDay || nextTimestamp.difference(currentTimestamp).inMinutes >= 20) {
                                        willShowTimestampForNext = true;
                                      }
                                    }

                                    if (currentSenderId != nextSenderId || willShowTimestampForNext) {
                                      showTimeBelow = true;
                                    }
                                  }

                                  return _buildMessageItem(
                                    messageData,
                                    messageId,
                                    showTimestamp: showTimestampForCurrent,
                                    formattedTimestamp: formattedTimestamp,
                                    showTimeBelow: showTimeBelow,
                                  );
                                },
                              ),
                  ),
                  _buildMessageComposer(),
                ],
              ),
              if (_showScrollToBottomButton)
                Positioned(
                  bottom: 80, // Position above the composer.
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FloatingActionButton(
                      mini: true,
                      onPressed: () {
                        _scrollController.animateTo(
                          0.0,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                        );
                      },
                      backgroundColor: Colors.white,
                      shape: const CircleBorder(),
                      child: const Icon(Icons.arrow_downward, color: Colors.blue),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
