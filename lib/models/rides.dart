import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';

class Ride {
  final String uid;
  final String userPictureURL;
  final String userName;
  final String drid;
  final String driverPictureURL;
  final String driverName;
  final GeoFirePoint? destinationAddress;
  final GeoFirePoint? pickupAddress;
  final Timestamp startTime; 
  final Timestamp endTime;    
  final String id;            
  final String status;

  Ride({
    required this.uid,
    required this.userName,
    required this.userPictureURL,
    required this.drid,
    required this.driverName,
    required this.driverPictureURL,
    required this.startTime,
    required this.endTime,
    required this.id,
    this.destinationAddress,
    this.pickupAddress,
    required this.status
  });

  Map<String, Object> toJson() {
    return {
      'uid': uid,
      'userName': userName,
      'userPictureURL': userPictureURL,
      'drid': drid,
      'driverName': driverName,
      'driverPictureURL': driverPictureURL,
      'destinationAddress': destinationAddress as Object,
      'pickupAddress': pickupAddress as Object,
      'status': status
    };
  }

  factory Ride.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      // print('doc = ');
      // print(json);
    }
    return Ride(
      uid: json['uid'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      userPictureURL: json['userPictureURL'] as String? ?? '',
      drid: json['drid'] as String? ?? '',
      driverName: json['driverName'] as String? ?? '',
      driverPictureURL: json['driverPictureURL'] as String? ?? '',
      status: json['status'] as String? ?? '',
      startTime: json["startTime"] as Timestamp? ?? Timestamp.now(),
      endTime: json["endTime"] as Timestamp? ?? Timestamp.now(),
      id: json["documentID"] as String? ?? ''
    );
  }

  factory Ride.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Ride.fromJson(data);
  }

  static GeoFirePoint extractGeoFirePoint(Map<String, dynamic> pointMap) {
    GeoPoint point = pointMap['geopoint'];
    return GeoFirePoint(point.latitude, point.longitude);
  }
}