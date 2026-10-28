import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
}

/// All Firebase + Google login logic lives here.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Only needed if Google login complains about a missing server client id.
  /// Firebase Console > Authentication > Sign-in method > Google >
  /// Web SDK configuration > Web client ID  (looks like xxxx.apps.googleusercontent.com)
  static const String? _webClientId = null;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _googleReady = false;

  Future<void> _initGoogle() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _googleReady = true;
  }

  Future<User?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.updateDisplayName(name.trim());
    return cred.user;
  }

  Future<User?> logIn({required String email, required String password}) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return cred.user;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<User?> signInWithGoogle() async {
    await _initGoogle();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw AuthException(
          'Google login is not supported on this device. Please use an Android phone or emulator.');
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw AuthException(
          'Google did not return a token. Check SHA-1 and the Web client ID in Firebase.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await _auth.signInWithCredential(credential);
    return result.user;
  }

  Future<void> signOut() async {
    try {
      await _initGoogle();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }
}

/// Turns any login error into a short, friendly message.
String friendlyError(Object e) {
  if (e is AuthException) return e.message;
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'operation-not-allowed':
        return 'This login method is not enabled in Firebase yet.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
  if (e is GoogleSignInException) {
    return e.code == GoogleSignInExceptionCode.canceled
        ? 'Google sign-in was cancelled.'
        : 'Google sign-in failed. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}