import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:zipapp/constants/zip_colors.dart';
import 'package:zipapp/constants/zip_design.dart';
import 'package:zipapp/ui/widgets/ride_activity_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zipapp/business/user.dart';
import 'package:geocoding/geocoding.dart';
import 'package:zipapp/services/payment.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<Ride> rides = [];
  bool isLoading = true; // Add isLoading variable
  final UserService userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late List<dynamic> pastRideIDs;

  @override
  void initState() {
    super.initState();
    _populateRideActivityData();
  }

  Future<List<Ride>> _retrievePastRides() async {
    QuerySnapshot rideQuerySnapshot = await _firestore
        .collection('rides')
        .where('uid', isEqualTo: userService.userID)
        .where('status', isNotEqualTo: "IN_PROGRESS")
        .orderBy('startTime', descending: true)
        .get();

    List<QueryDocumentSnapshot> rideDocs = rideQuerySnapshot.docs;

    List<Future<Ride>> rideDetailsFutures = rideDocs.map((ride) async {
      var destinationGeoPoint =
          (await ride.get('destinationAddress'))['geopoint'];
      var pickupGeoPoint = (await ride.get('pickupAddress'))['geopoint'];
      var destination = (await _getAddressFromGeoPoint(destinationGeoPoint));
      var startTime = (ride.get('startTime') as Timestamp).toDate();
      var endTime = (ride.get('endTime') as Timestamp).toDate();
      var origin = await _getAddressFromGeoPoint(pickupGeoPoint);
      var price = ride.get('price');
      var id = ride.id;
      var tip = await _firestore
          .collection('ratings')
          .where('rideID', isEqualTo: id)
          .get()
          .then((ratingQuerySnapshot) => ratingQuerySnapshot.docs.isNotEmpty
              ? ratingQuerySnapshot.docs[0].get('tip')
              : 0.0);
      var rating = await _firestore
          .collection('ratings')
          .where('rideID', isEqualTo: id)
          .get()
          .then((ratingQuerySnapshot) => ratingQuerySnapshot.docs.isNotEmpty
              ? ratingQuerySnapshot.docs[0].get('rating')
              : 0);
      Map<String, dynamic>? paymentDetails =
          await Payment.loadPaymentIntentDetails(userService.userID, id);

      return Ride(
        destination: destination,
        startTime: startTime,
        endTime: endTime,
        origin: origin,
        price: price,
        id: id,
        tip: tip,
        rating: rating,
        status: ride.get('status'),
        cardUsed: paymentDetails != null ? paymentDetails['cardUsed'] : null,
        last4: paymentDetails != null ? paymentDetails['last4'] : null,
        paymentMethod:
            paymentDetails != null ? paymentDetails['paymentMethod'] : null,
      );
    }).toList();

    return await Future.wait(rideDetailsFutures);
  }

  Future<String> _getAddressFromGeoPoint(GeoPoint geoPoint) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        geoPoint.latitude,
        geoPoint.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String address = "${place.street}, ${place.locality}";
        if (place.name != null) {
          address =
              "${place.name} - ${place.locality}, ${place.administrativeArea}";
        }
        return address;
      } else {
        return "No address available";
      }
    } catch (e) {
      return "Error occurred: $e";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZipColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: ZipColors.primaryBackground,
        title: const Text(
          'Activity',
          style: ZipDesign.pageTitleText,
        ),
        scrolledUnderElevation: 0,
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
              color: ZipColors.lightGray,
            )) // Show loading indicator
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Past',
                    textAlign: TextAlign.left,
                    style: ZipDesign.sectionTitleText,
                  ),
                  rides.isNotEmpty
                      ? Expanded(
                          child: ListView.builder(
                            itemCount: rides.length,
                            itemBuilder: (context, index) {
                              return RideActivityItem(
                                destination: rides[index].destination,
                                origin: rides[index].origin,
                                startTime: rides[index].startTime,
                                endTime: rides[index].endTime,
                                price: rides[index].price,
                                id: rides[index].id,
                                tip: rides[index].tip,
                                rating: rides[index].rating,
                                status: rides[index].status,
                                cardUsed: rides[index].cardUsed,
                                last4: rides[index].last4,
                                paymentMethod: rides[index].paymentMethod,
                              );
                            },
                          ),
                        )
                      : const Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Icon(LucideIcons.car,
                                  size: 75, color: ZipColors.lightGray),
                              Text(
                                "No past rides, let's go for a ride!",
                                style: ZipDesign.disabledBodyText,
                              ),
                            ],
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  void _populateRideActivityData() async {
    setState(() {
      isLoading = true; // Start loading
    });
    List<Ride> tempRides = await _retrievePastRides();
    setState(() {
      rides = tempRides;
      isLoading = false; // Stop loading
    });
  }
}

class Ride {
  final String destination;
  final DateTime startTime;
  final DateTime endTime;
  final double price;
  final String origin;
  final String id;
  final double tip;
  final int rating;
  final String status;
  final String? cardUsed;
  final String? last4;
  final String? paymentMethod;
  Ride(
      {required this.destination,
      required this.startTime,
      required this.endTime,
      required this.price,
      required this.origin,
      required this.id,
      required this.tip,
      required this.rating,
      required this.status,
      this.cardUsed,
      this.last4,
      this.paymentMethod});
}
