import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

class AuthState extends ChangeNotifier {
  final AuthService _authService;

  User? user;
  bool isAdmin = false;
  bool isLoading = true;

  StreamSubscription<User?>? _sub;

  AuthState({AuthService? authService}) : _authService = authService ?? AuthService() {
    _sub = _authService.authStateChanges.listen(_onAuthChanged);
  }

  Future<void> _onAuthChanged(User? newUser) async {
    user = newUser;
    isAdmin = newUser == null ? false : await _authService.isCurrentUserAdmin();
    isLoading = false;
    notifyListeners();
  }

  /// Signs in and resolves admin status directly, rather than waiting on the
  /// authStateChanges listener — that reactive path was found to be
  /// unreliable for driving navigation right after a fresh sign-in.
  Future<String?> signIn({required String email, required String password}) async {
    try {
      await _authService.signIn(email: email, password: password);
      user = _authService.currentUser;
      isAdmin = await _authService.isCurrentUserAdmin();
      isLoading = false;
      notifyListeners();
      if (!isAdmin) {
        return 'This account is not authorized as an admin.';
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Sign-in failed';
    }
  }

  Future<void> signOut() => _authService.signOut();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
