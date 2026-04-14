// import 'dart:collection';
// import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
// import 'package:geoflutterfire/geoflutterfire.dart';
import '../utils.dart';

class Driver {
  final String uid;
  final String firstName;
  final String lastName;
  final String cartModel;
  final String profilePictureURL;
  final DateTime lastActivity;
  final String fcmToken; // Firebase Cloud Messaging Token
  final bool isWorking;
  final bool isAvailable;
  final GeoFirePoint? geoFirePoint;
  final String currentRideID;
  final List<int> daysOfWeek;
  final bool isOnBreak;

  Driver(
      {required this.uid,
      required this.firstName,
      required this.lastName,
      required this.cartModel,
      required this.lastActivity,
      required this.profilePictureURL,
      this.geoFirePoint,
      required this.fcmToken,
      required this.isWorking,
      required this.isAvailable,
      required this.currentRideID,
      required this.daysOfWeek,
      required this.isOnBreak});

  Map<String, Object> toJson() {
    return {
      'uid': uid,
      'firstName': firstName,
      'lastName': lastName,
      'cartModel': cartModel,
      'lastActivity': lastActivity,
      'profilePictureURL': profilePictureURL,
      'geoFirePoint': geoFirePoint as Object,
      'fcmToken': fcmToken,
      'isWorking': isWorking,
      'isAvailable': isAvailable,
      'currentRideID': currentRideID,
      'daysOfWeek': daysOfWeek,
      'isOnBreak': isOnBreak
    };
  }

  factory Driver.fromJson(Map<String, dynamic> doc) {
    final Timestamp? lastActivityStamp = doc['lastActivity'] as Timestamp?;
    final Map<String, dynamic>? geoPointMap =
        doc['geoFirePoint'] as Map<String, dynamic>?;

    Driver driver = Driver(
      uid: (doc['uid'] as String?) ?? '',
      firstName: (doc['firstName'] as String?) ?? '',
      lastName: (doc['lastName'] as String?) ?? '',
      cartModel: (doc['cartModel'] as String?) ?? 'X',
      lastActivity: lastActivityStamp != null
          ? convertStamp(lastActivityStamp)
          : DateTime.fromMillisecondsSinceEpoch(0),
      profilePictureURL: (doc['profilePictureURL'] as String?) ?? '',
      geoFirePoint:
          geoPointMap != null ? extractGeoFirePoint(geoPointMap) : null,
      fcmToken: (doc['fcmToken'] as String?) ?? '',
      isWorking: doc['isWorking'] as bool? ?? false,
      isAvailable: doc['isAvailable'] as bool? ?? false,
      isOnBreak: doc['isOnBreak'] as bool? ?? false,
      currentRideID: (doc['currentRideID'] as String?) ?? '',
      daysOfWeek: List<int>.from((doc['daysOfWeek'] as List?) ?? const []),
    );
    return driver;
  }

  factory Driver.fromDocument(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    data.putIfAbsent('uid', () => doc.id);
    return Driver.fromJson(data);
  }

  static GeoFirePoint extractGeoFirePoint(Map<String, dynamic> pointMap) {
    GeoPoint point = pointMap['geopoint'];
    return GeoFirePoint(point.latitude, point.longitude);
  }

  static List<int> daysOfWeekConvert(List workDays) {
    Map dayConvert = <String, int>{};
    dayConvert['sunday'] = 0;
    dayConvert['monday'] = 1;
    dayConvert['tuesday'] = 2;
    dayConvert['wednesday'] = 3;
    dayConvert['thursday'] = 4;
    dayConvert['friday'] = 5;
    dayConvert['saturday'] = 6;

    for (var i = 0; i < workDays.length; i++) {
      String temp = workDays[i].toLowerCase();
      workDays[i] = dayConvert[temp];
    }
    return workDays as List<int>;
  }
}

class CurrentShift {
  final DateTime shiftStart;
  final DateTime shiftEnd;
  final DateTime startTime;
  final DateTime endTime;
  final int totalBreakTime;
  final int totalShiftTime;
  final DateTime breakStart;
  final DateTime breakEnd;

  CurrentShift(
      {required this.shiftStart,
      required this.shiftEnd,
      required this.startTime,
      required this.endTime,
      required this.totalBreakTime,
      required this.totalShiftTime,
      required this.breakStart,
      required this.breakEnd});

  Map<String, Object> toJson() {
    return {
      'shiftStart': shiftStart,
      'shiftEnd': shiftEnd,
      'startTime': startTime,
      'endTime': endTime,
      'totalBreakTime': totalBreakTime,
      'totalShiftTime': totalShiftTime,
      'breakStart': breakStart,
      'breakEnd': breakEnd,
    };
  }

  factory CurrentShift.fromJson(Map<String, dynamic> doc) {
    CurrentShift shift = CurrentShift(
        shiftStart: convertStamp(doc['shiftStart'] as Timestamp),
        shiftEnd: convertStamp(doc['shiftEnd'] as Timestamp),
        startTime: convertStamp(doc['startTime'] as Timestamp),
        endTime: convertStamp(doc['endTime'] as Timestamp),
        totalBreakTime: doc['totalBreakTime'] as int,
        totalShiftTime: doc['totalShiftTime'] as int,
        breakStart: convertStamp(doc['breakStart'] as Timestamp),
        breakEnd: convertStamp(doc['breakEnd'] as Timestamp));
    return shift;
  }

  factory CurrentShift.fromDocument(DocumentSnapshot doc) {
    return CurrentShift.fromJson(doc.data() as Map<String, dynamic>);
  }
}
