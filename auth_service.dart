import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/person.dart';

// Handles user authentication
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.isEmpty || parts.first.isEmpty) return 'U';

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Future<Person> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim().isEmpty ? 'User' : name.trim();
    final cleanEmail = email.trim();

    final credential = await _auth.createUserWithEmailAndPassword(
      email: cleanEmail,
      password: password.trim(),
    );

    final user = credential.user;

    if (user == null) {
      throw Exception('Could not create account.');
    }

    await user.updateDisplayName(cleanName);

    final person = Person(
      id: user.uid,
      name: cleanName,
      subtitle: cleanEmail,
      initials: _initialsFromName(cleanName),
    );

    await _db.collection('users').doc(user.uid).set({
      ...person.toMap(),
      'email': cleanEmail,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return person;
  }

  Future<Person> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    if (credential.user == null) {
      throw Exception('Could not sign in.');
    }

    return getCurrentPerson();
  }

  Future<void> resetPassword(String email) async {
    final cleanEmail = email.trim();

    if (cleanEmail.isEmpty) {
      throw Exception('Please enter your email address first.');
    }

    await _auth.sendPasswordResetEmail(email: cleanEmail);
  }

  Future<Person> getCurrentPerson() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No user logged in.');
    }

    final ref = _db.collection('users').doc(user.uid);
    final doc = await ref.get();

    if (doc.exists && doc.data() != null) {
      return Person.fromMap(doc.data()!);
    }

    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : 'User';

    final person = Person(
      id: user.uid,
      name: name,
      subtitle: user.email ?? '',
      initials: _initialsFromName(name),
    );

    await ref.set({
      ...person.toMap(),
      'email': user.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return person;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
