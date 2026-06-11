import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

enum UserRole { guest, user, admin, superAdmin }

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  User? _user;
  UserRole? _role; // Change to nullable to represent uninitialized/no role chosen
  bool _isLoading = true;
  String? _currentDeviceId;
  String? _logoutReason;
  
  User? get user => _user;
  UserRole get role => _role ?? UserRole.user; // Default to user if not guest
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  bool get isGuest => _role == UserRole.guest;
  String? get logoutReason => _logoutReason;

  void clearLogoutReason() {
    _logoutReason = null;
    notifyListeners();
  }

  AuthService() {
    _initDeviceId();
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _initDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _currentDeviceId = androidInfo.id; // Unique ID for the device
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _currentDeviceId = iosInfo.identifierForVendor;
      } else if (Platform.isWindows) {
        final winInfo = await _deviceInfo.windowsInfo;
        _currentDeviceId = winInfo.deviceId;
      }
    } catch (e) {
      _currentDeviceId = 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    _user = firebaseUser;
    if (_user == null) {
      // If we were a guest before, stay a guest. Otherwise, no role.
      if (_role != UserRole.guest) {
        _role = null; 
      }
      _isLoading = false;
      notifyListeners();
    } else {
      await _setupUserSession();
    }
  }

  Future<void> _setupUserSession() async {
    if (_user == null) return;
    
    try {
      final docRef = _firestore.collection('users').doc(_user!.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        // BOOTSTRAP LOGIC: If this is the FIRST user ever, make them Super Admin
        final usersSnapshot = await _firestore.collection('users').limit(1).get();
        final role = usersSnapshot.docs.isEmpty ? 'super_admin' : 'user';

        await docRef.set({
          'email': _user!.email,
          'role': role,
          'accessible_banks': [],
          'current_device_id': _currentDeviceId,
          'created_at': FieldValue.serverTimestamp(),
        });
        _role = _parseRole(role);
      } else {
        // Update the current device ID in Firestore for this login
        await docRef.update({'current_device_id': _currentDeviceId});
        _role = _parseRole(doc.data()!['role']);
      }

      // Start listening for session changes (Live Force Logout)
      docRef.snapshots().listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data()!;
          final cloudDeviceId = data['current_device_id'] as String?;
          
          if (cloudDeviceId != null && cloudDeviceId != _currentDeviceId) {
            // Logged in on another device!
            _logoutReason = "Logged in on another device.";
            signOut();
          }
        }
      });

    } catch (e) {
      debugPrint('Error setting up user session: $e');
      _role = UserRole.user;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  UserRole _parseRole(String? roleStr) {
    switch (roleStr) {
      case 'super_admin': return UserRole.superAdmin;
      case 'admin': return UserRole.admin;
      case 'user': return UserRole.user;
      default: return UserRole.user;
    }
  }

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUp(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    if (credential.user != null) {
      await credential.user!.sendEmailVerification();
    }
  }

  Future<void> reloadUser() async {
    if (_user != null) {
      await _user!.reload();
      _user = _auth.currentUser;
      notifyListeners();
    }
  }

  Future<void> sendVerificationEmail() async {
    if (_user != null) {
      await _user!.sendEmailVerification();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  void continueAsGuest() {
    _user = null;
    _role = UserRole.guest;
    _isLoading = false;
    notifyListeners();
  }
}
