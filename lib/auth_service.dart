import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Signs up a user with the given email and password using Firebase.
  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String dob,
  }) async {
    print('Attempting to sign up with Firebase for email: $email');
    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // After successful sign-up, store additional user data in Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'fullName': fullName,
        'dob': dob,
        'email': email,
      });

      print('Firebase sign up successful for $email');
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        print('The password provided is too weak.');
        return 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        print('The account already exists for that email.');
        return 'An account already exists for that email.';
      }
      print('Firebase sign up failed: ${e.message}');
      return e.message;
    } catch (e) {
      print('An unexpected error occurred during sign up: $e');
      return 'An unexpected error occurred during sign up.';
    }
  }

  /// Signs in a user with the given email and password using Firebase.
  Future<bool> signIn({required String email, required String password}) async {
    print('Attempting to sign in with Firebase for email: $email');
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('Firebase sign in successful for $email');
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        print('No user found for that email.');
      } else if (e.code == 'wrong-password') {
        print('Wrong password provided for that user.');
      }
      print('Firebase sign in failed: ${e.message}');
      return false;
    } catch (e) {
      print('An unexpected error occurred during sign in: $e');
      return false;
    }
  }
}
