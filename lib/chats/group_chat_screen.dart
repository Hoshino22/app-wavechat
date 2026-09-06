import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:wavechat/chats/add_members_screen.dart';
import 'package:wavechat/chats/group_members_screen.dart';
import 'package:wavechat/utils/ui_helper.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatScreen({Key? key, required this.groupId, required this.groupName})
      : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _messageController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late Stream<DocumentSnapshot> _groupStream;
  String _currentGroupName = '';

  // Pagination and real-time state
  final _scrollController = ScrollController();
  List<DocumentSnapshot> _messages = [];
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  StreamSubscription? _messageStreamSubscription;
  static const int _messagesLimit = 20;
  OverlayEntry? _unsendOverlay;
  bool _showScrollToBottomButton = false;

  @override
  void initState() {
    super.initState();
    _currentGroupName = widget.groupName;
    _groupStream = _firestore.collection('groups').doc(widget.groupId).snapshots();
    _groupStream.listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          final data = snapshot.data() as Map<String, dynamic>?;
          _currentGroupName = data?['groupName'] ?? _currentGroupName;
        });
      }
    });
    _fetchInitialMessages();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _groupNameController.dispose();
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

  Future<void> _fetchInitialMessages() async {
    if (!mounted) return;
    setState(() {
      _isLoadingInitial = true;
    });

    try {
      final query = _firestore
          .collection('groups')
          .doc(widget.groupId)
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
          .collection('groups')
          .doc(widget.groupId)
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
        .collection('groups')
        .doc(widget.groupId)
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
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final senderName = userDoc.data()?['fullName'] ?? 'Unknown User';
      final messageText = _messageController.text.trim();

      final groupRef = _firestore.collection('groups').doc(widget.groupId);
      final messageRef = groupRef.collection('messages').doc();

      final batch = _firestore.batch();

      batch.set(messageRef, {
        'text': messageText,
        'senderId': user.uid,
        'senderName': senderName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      batch.update(groupRef, {
        'lastMessage': messageText,
        'lastMessageSenderId': user.uid,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'readBy': [user.uid],
      });

      await batch.commit();

      _messageController.clear();

      // --- Send notifications to group members ---
      final groupDoc = await _firestore.collection('groups').doc(widget.groupId).get();
      final groupData = groupDoc.data();
      if (groupData != null && groupData.containsKey('members')) {
        final List<String> members = List<String>.from(groupData['members']);
        final notificationBatch = _firestore.batch();

        for (final memberId in members) {
          if (memberId != user.uid) {
            final notificationRef = _firestore.collection('notifications').doc();
            notificationBatch.set(notificationRef, {
              'recipientId': memberId,
              'senderId': user.uid,
              'senderName': senderName,
              'type': 'GROUP_MESSAGE',
              'groupId': widget.groupId,
              'groupName': _currentGroupName,
              'body': messageText.length > 30
                  ? '${messageText.substring(0, 30)}...'
                  : messageText,
              'isRead': false,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
        }
        await notificationBatch.commit();
      }
    } catch (e) {
      if (mounted)
        showStyledSnackBar(context, 'Failed to send message: $e', isError: true);
    }
  }

  Future<void> _unsendMessage(String messageId) async {
    final groupRef = _firestore.collection('groups').doc(widget.groupId);
    final messageRef = groupRef.collection('messages').doc(messageId);

    setState(() {
      _messages.removeWhere((msg) => msg.id == messageId);
    });

    try {
      await messageRef.delete();

      final lastMessageSnapshot = await groupRef
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (lastMessageSnapshot.docs.isNotEmpty) {
        final lastMessage = lastMessageSnapshot.docs.first.data();
        await groupRef.update({
          'lastMessage': lastMessage['text'],
          'lastMessageSenderId': lastMessage['senderId'],
          'lastMessageTimestamp': lastMessage['timestamp'],
        });
      } else {
        await groupRef.update({
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


  Future<void> _deleteGroup() async {
    final messages = await _firestore
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .get();
    final batch = _firestore.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    await _firestore.collection('groups').doc(widget.groupId).delete();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _updateGroupName() async {
    if (_groupNameController.text.trim().isEmpty) return;
    await _firestore.collection('groups').doc(widget.groupId).update({
      'groupName': _groupNameController.text.trim(),
    });
    if (mounted) Navigator.of(context).pop();
    _groupNameController.clear();
  }

  void _showEditGroupNameDialog() {
    _groupNameController.text = _currentGroupName;
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Edit Group Name'),
              content: TextField(
                  controller: _groupNameController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Enter new name')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                TextButton(
                    onPressed: _updateGroupName,
                    child: const Text('Save', style: TextStyle(color: Colors.blue))),
              ],
            ));
  }

  void _showDeleteGroupDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Delete Group'),
              content: const Text(
                  'Are you sure you want to permanently delete this group?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Colors.blue))),
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _deleteGroup();
                    },
                    child: const Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ));
  }

  Future<void> _leaveGroup() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('groups').doc(widget.groupId).update({
        'members': FieldValue.arrayRemove([user.uid]),
      });
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Failed to leave group: $e', isError: true);
      }
    }
  }

  void _showLeaveGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _leaveGroup();
            },
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(DocumentSnapshot messageDoc,
      {bool showSenderName = false,
      bool showTimestamp = false,
      String formattedTimestamp = '',
      bool showTimeBelow = false}) {
    final messageData = messageDoc.data() as Map<String, dynamic>;
    final isMe = messageData['senderId'] == _auth.currentUser?.uid;
    final senderName = messageData['senderName'] as String? ?? 'Unknown';
    final timestamp = messageData['timestamp'] as Timestamp?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe && showSenderName)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 2.0),
                  child: Text(
                    senderName,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              Builder(builder: (itemContext) {
                return GestureDetector(
                  onLongPress: () {
                    if (!isMe) return;
                    _showUnsendOverlay(itemContext, messageDoc.id);
                  },
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
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
                );
              }),
              if (showTimeBelow)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4, left: 4, bottom: 4),
                  child: Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Text(
                      timestamp != null
                          ? DateFormat.jm().format(timestamp.toDate())
                          : '',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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
          title: Text(_currentGroupName),
          backgroundColor: const Color(0xFF1E88E5),
          foregroundColor: Colors.white,
          actions: [
            StreamBuilder<DocumentSnapshot>(
              stream: _groupStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final groupData = snapshot.data!.data() as Map<String, dynamic>?;
                final isCreator = groupData?['createdBy'] == _auth.currentUser?.uid;

                return PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'view_members') {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  GroupMembersScreen(groupId: widget.groupId)));
                    } else if (value == 'leave_group') {
                      _showLeaveGroupDialog();
                    }

                    if (!isCreator) {
                      return;
                    }

                    if (value == 'edit_name') {
                      _showEditGroupNameDialog();
                    } else if (value == 'add_members') {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => AddMembersScreen(
                                  groupId: widget.groupId,
                                  currentMembers: List<String>.from(
                                      groupData?['members'] ?? []))));
                    } else if (value == 'delete_group') {
                      _showDeleteGroupDialog();
                    }
                  },
                  itemBuilder: (context) {
                    final groupData =
                        snapshot.data!.data() as Map<String, dynamic>?;
                    final isCreator =
                        groupData?['createdBy'] == _auth.currentUser?.uid;

                    return [
                      const PopupMenuItem<String>(
                          value: 'view_members', child: Text('View Members')),
                      if (isCreator) ...[
                        const PopupMenuItem<String>(
                            value: 'edit_name', child: Text('Edit Name')),
                        const PopupMenuItem<String>(
                            value: 'add_members', child: Text('Add Members')),
                        const PopupMenuItem<String>(
                            value: 'delete_group',
                            child: Text('Delete Group',
                                style: TextStyle(color: Colors.red))),
                      ],
                      if (!isCreator)
                        const PopupMenuItem<String>(
                            value: 'leave_group',
                            child: Text('Leave Group',
                                style: TextStyle(color: Colors.red))),
                    ];
                  },
                );
              },
            ),
          ],
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
                                  final messageDoc = _messages[index];
                                  final messageData = messageDoc.data() as Map<String, dynamic>;

                                  // --- Timestamp logic ---
                                  final currentTimestampData =
                                      messageData['timestamp'] as Timestamp?;
                                  bool showTimestampForCurrent = false;
                                  String formattedTimestamp = '';

                                  if (currentTimestampData != null) {
                                    final currentTimestamp = currentTimestampData.toDate();
                                    if (index == _messages.length - 1) {
                                      // Oldest message
                                      showTimestampForCurrent = true;
                                      formattedTimestamp =
                                          DateFormat.yMMMd().add_jm().format(currentTimestamp);
                                    } else {
                                      final previousMessageData =
                                          _messages[index + 1].data() as Map<String, dynamic>;
                                      final previousTimestampData =
                                          previousMessageData['timestamp'] as Timestamp?;
                                      if (previousTimestampData != null) {
                                        final previousTimestamp =
                                            previousTimestampData.toDate();
                                        final isNewDay =
                                            currentTimestamp.day != previousTimestamp.day ||
                                                currentTimestamp.month !=
                                                    previousTimestamp.month ||
                                                currentTimestamp.year != previousTimestamp.year;

                                        if (isNewDay) {
                                          showTimestampForCurrent = true;
                                          formattedTimestamp = DateFormat.yMMMd()
                                              .add_jm()
                                              .format(currentTimestamp);
                                        } else if (currentTimestamp
                                                .difference(previousTimestamp)
                                                .inMinutes >=
                                            20) {
                                          showTimestampForCurrent = true;
                                          formattedTimestamp =
                                              DateFormat.jm().format(currentTimestamp);
                                        }
                                      }
                                    }
                                  }

                                  // --- Sender Name and Time Below logic ---
                                  bool showSenderName = false;
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
                                       final currentTimestamp = currentTimestampData!.toDate();
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

                                  if (index < _messages.length - 1) {
                                      final previousMessageData = _messages[index + 1].data() as Map<String, dynamic>;
                                      final previousSenderId = previousMessageData['senderId'];
                                      if (currentSenderId != previousSenderId || showTimestampForCurrent) {
                                          showSenderName = true;
                                      }
                                  } else {
                                      showSenderName = true; // Always show for the very first message
                                  }

                                  return _buildMessageItem(
                                    messageDoc,
                                    showSenderName: showSenderName,
                                    showTimestamp: showTimestampForCurrent,
                                    formattedTimestamp: formattedTimestamp,
                                    showTimeBelow: showTimeBelow,
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
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.blue),
                          onPressed: _sendMessage,
                        ),
                      ],
                    ),
                  ),
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
