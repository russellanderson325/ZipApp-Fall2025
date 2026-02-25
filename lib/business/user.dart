/*
 * user.dart
 * This file contains the User class and the UserService class.
 */
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:zipapp/models/user.dart';
import 'package:zipapp/logger.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String userID = '';
  late Stream<User> userStream;
  late StreamSubscription userSub;
  late User user;

  final AppLogger logger = AppLogger();

  factory UserService() {
    return _instance;
  }

  UserService._internal() {
    if (kDebugMode) {
      // print("UserService Created with user: $userID");
    }
  }

  void startRide(rideId) {
    logger.info(userID);
    // if isRiding exists in the user document, set it to true
    _db.collection("users").doc(userID).set({
      "isRiding": true,
      "currentRideId": rideId,
    }, SetOptions(merge: true)).then((_) {
      logger.info("Successfully started ride.");
    }).catchError((error) {
      logger.error("Error starting ride: $error");
    });

    // Start listening for ride updates
  }

  void endRide() {
    // if isRiding field exists in the user document, set it to false
    _db.collection("users").doc(userID).set({
      "isRiding": false,
      "currentRideId": "",
    }, SetOptions(merge: true)).then((_) {
      logger.info("Successfully ended ride.");
    }).catchError((error) {
      logger.error("Error ending ride: $error");
    });

    // Reset the map
  }

  bool isRiding() {
    return user.isRiding;
  }

  String getRideId() {
    return user.currentRideId;
  }

  void setupService(String id) {
    if (userID != id) {
      //userSub.cancel();
      userID = id;
      userStream = _db
          .collection("users")
          .doc(userID)
          .snapshots()
          .map((DocumentSnapshot snapshot) {
        return User.fromDocument(snapshot);
      });
      userSub = userStream.listen((user) {
        this.user = user;
      });
      logger.info("UserService setup with user: $userID");
    }
  }

  Stream<User> getUserStream() {
    return _db
        .collection("users")
        .doc(userID)
        .snapshots()
        .map((DocumentSnapshot snapshot) {
      return User.fromDocument(snapshot);
    });
  }
}
