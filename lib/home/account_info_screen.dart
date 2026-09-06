import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wavechat/utils/color_helper.dart';
import 'package:wavechat/utils/ui_helper.dart';

class AccountInfoScreen extends StatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
        print("Error fetching user data: $e");
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

  Future<void> _updateUserName(String newName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || newName.trim().isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'fullName': newName.trim()});

      if (mounted) {
        setState(() {
          if(_userData != null) {
            _userData!['fullName'] = newName.trim();
          }
        });
        showStyledSnackBar(context, 'Name updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        showStyledSnackBar(context, 'Failed to update name: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showEditNameDialog(BuildContext context, String currentName) {
    _nameController.text = currentName;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Name'),
          content: TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter your new name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                _updateUserName(_nameController.text);
                Navigator.of(context).pop();
              },
              child: const Text('Save', style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String initial = '';
    String userName = 'Loading...';
    String userEmail = '';
    String userDob = '';

    if (!_isLoading && _userData != null) {
      userName = _userData!['fullName'] ?? 'No Name';
      userEmail = _userData!['email'] ?? 'N/A';
      userDob = _userData!['dob'] ?? 'N/A';
      if (userName.isNotEmpty && userName != 'Loading...') {
        initial = userName[0].toUpperCase();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Info'),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userData == null
              ? const Center(child: Text('No user data found.'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: getAvatarColor(initial),
                          child: Text(
                            initial,
                            style: const TextStyle(fontSize: 50, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildProfileDetail(
                        label: 'Name',
                        value: userName,
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.grey),
                          onPressed: () => _showEditNameDialog(context, userName),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildProfileDetail(label: 'Email', value: userEmail),
                      const SizedBox(height: 16),
                      _buildProfileDetail(label: 'Date of Birth', value: userDob),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProfileDetail({required String label, required String value, Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const Divider(),
      ],
    );
  }
}
