/*
 * ride.dart
 * This file contains the RideService class which is responsible for managing the user's ride.
 */
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:zipapp/business/drivers.dart';
import 'package:zipapp/business/location.dart';
import 'package:zipapp/business/user.dart';
import 'package:zipapp/models/driver.dart';
import 'package:zipapp/models/request.dart';
import 'package:zipapp/models/rides.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

class RideService {
  static final RideService _instance = RideService._internal();
  final bool showDebugPrints = true;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late DocumentReference rideReference;
  late DocumentReference currentRidesReference;
  late bool isSearchingForRide;
  late bool goToNextDriver;
  late Stream<Ride> rideStream;
  late StreamSubscription rideSubscription;
  late Ride ride;
  late bool removeRide;
  late double pickupRadius;
  String? rideID;
  Driver? acceptedDriver;
  // Services
  LocationService locationService = LocationService();
  DriverService driverService = DriverService();
  UserService userService = UserService();
  // Subscriptions
  late Stream<List<DocumentSnapshot>> nearbyDrivers;

  /*
   * Singleton constructor for RideService
   * @return RideService
   */
  factory RideService() {
    return _instance;
  }

  setupService() async {
    rideStream = rideReference
        .snapshots()
        .map((snapshot) => Ride.fromDocument(snapshot))
        .asBroadcastStream();
  }

  /*
   * Internal constructor for RideService
   * Initializes the Firestore references for the rides and current rides collections
   * and sets the rideID to the ID of the ride document.
   * @return RideService
   */
  RideService._internal() {
    if (userService.user.currentRideId != "" && userService.user.isRiding) {
      rideID = userService.user.currentRideId;
      rideReference = _firestore.collection('rides').doc(rideID);
    }

    currentRidesReference =
        _firestore.collection('CurrentRides').doc('currentRides');
  }

  void initializeRideWithoutID() async {
    print('Initializing ride without ID');
    rideReference = _firestore.collection('rides').doc();
    rideID = rideReference.id;
    currentRidesReference =
        _firestore.collection('CurrentRides').doc('currentRides');
    ride = await rideReference.get().then((snapshot) {
      return Ride.fromDocument(snapshot);
    });
    setupService();
  }

  bool hasActiveDriverConnection() {
    return rideID != null && 
           acceptedDriver != null && 
           ride.status == "IN_PROGRESS";
  }

  Future<void> updateRideDirections(List<String> newDirections) async {
    if (!hasActiveDriverConnection()) {
      throw Exception(
        'Currently there is no driver connection to the rider. '
        'Must create a ride object and connect the two first, '
        'then can modify directions given to the drivers.'
      );
    }
    
    await rideReference.update({
      'directions': newDirections,
      'lastActivity': DateTime.now(),
    });
    
    if (showDebugPrints) {
      print("Directions updated: $newDirections");
    }
  }

  Future<void> sendDirectionsToDriver(List<String> directions) async {
    if (!hasActiveDriverConnection()) {
      throw Exception(
        'Currently there is no driver connection to the rider. '
        'Must create a ride object and connect the two first, '
        'then can modify directions given to the drivers.'
      );
    }
    
    await _firestore
        .collection('drivers')
        .doc(acceptedDriver!.uid)
        .update({
      'currentDirections': directions,
      'directionsUpdatedAt': DateTime.now(),
    });
  }

  Map<String, dynamic> getConnectionStatus() {
    return {
      'hasRideID': rideID != null,
      'hasAcceptedDriver': acceptedDriver != null,
      'rideStatus': ride.status,
      'isConnected': hasActiveDriverConnection(),
      'driverName': acceptedDriver?.firstName ?? 'No driver assigned',
    };
  }

  Future<void> startRide(
      double lat, double long, double paymentPrice, String model) async {
    print('RIDER: ===== STARTING RIDE REQUEST =====');
    print('RIDER: Destination: $lat, $long');
    print('RIDER: Price: \$${paymentPrice.toStringAsFixed(2)}');
    print('RIDER: Model requested: $model');
    
    await _initializeRideInFirestore(lat, long, paymentPrice);
    print('RIDER: Ride initialized in Firestore (ID: $rideID)');
    
    rideStream = rideReference
        .snapshots()
        .map((snapshot) => Ride.fromDocument(snapshot))
        .asBroadcastStream();
    rideSubscription = rideStream.listen(_onRideUpdate);
    int timesSearched = 0;
    double radius = 1;
    isSearchingForRide = true;
    goToNextDriver = false;

    print('RIDER: ===== STARTING DRIVER SEARCH =====');

    while (isSearchingForRide) {
      print('RIDER: Search iteration ${timesSearched + 1}');
      print('RIDER: Searching with radius: $radius miles');
      
      List<Driver> nearbyDrivers =
          await driverService.getNearbyDriversListWithModel(radius, model);
      
      print('RIDER: Found ${nearbyDrivers.length} nearby drivers');
      
      if (nearbyDrivers.isNotEmpty && timesSearched < 6) {
        for (int i = 0; i < nearbyDrivers.length; i++) {
          if (isSearchingForRide) {
            Driver driver = nearbyDrivers[i];
            print('RIDER: Sending request to driver ${i + 1}/${nearbyDrivers.length}');
            print('  - Name: ${driver.firstName} ${driver.lastName}');
            print('  - UID: ${driver.uid}');
            print('  - Model: ${driver.cartModel}');
            
            await rideReference.update({'status': 'WAITING'});
            bool driverAccepted =
                await _sendRequestToDriver(driver, model, paymentPrice);
            if (driverAccepted) {
              print('RIDER: Driver accepted the ride!');
              acceptedDriver = driver;
            } else {
              print('RIDER: Driver did not accept (timeout)');
            }
          }
        }
        timesSearched += 1;
      } else {
        print('RIDER: No drivers found, expanding search radius');
        timesSearched += 1;
        radius += 10;
        if (timesSearched > 5) {
          print('RIDER: Max search attempts reached, giving up');
          isSearchingForRide = false;
        } else {
          print('RIDER: Waiting 60 seconds before next search...');
          await Future.delayed(const Duration(seconds: 60));
        }
      }
    }
    
    print('RIDER: ===== SEARCH COMPLETE =====');
    
    if (ride.status == "IN_PROGRESS") {
      print('RIDER: Ride is in progress!');
    } else {
      print('RIDER: No driver found, canceling ride');
      await rideReference
          .update({'lastActivity': DateTime.now(), 'status': "CANCELED"});
    }
  }

  /*
  * Cancel the ride. Update the status of the ride in firestore, cancel the ride subscription 
  * and remove the rider from the current rides collection.
  * @return void
  */
  void cancelRide() async {
    isSearchingForRide = false;
    goToNextDriver = true;
    try {
      rideSubscription.cancel();
    } catch (e) {
      // do nothing
    }
    DocumentSnapshot myRide = await rideReference.get();
    if (acceptedDriver != null)
      _getDriverReference(acceptedDriver!.uid)
          .collection('requests')
          .doc(rideID)
          .delete();
    if (myRide.exists) {
      removeCurrentRider();
      rideReference.update({
        'lastActivity': DateTime.now(),
        'status': "CANCELED",
      });
      // reset rideReference
      rideReference = _firestore.collection('rides').doc();
    }
  }

  void endRide() async {
    rideSubscription.cancel();
    rideReference.update({
      'lastActivity': DateTime.now(),
      'status': "ENDED",
    });
    rideReference = _firestore.collection('rides').doc();
  }

  _getDriverReference(String driverID) {
    return _firestore.collection('drivers').doc(driverID);
  }

  Future<bool> _sendRequestToDriver(
      Driver driver, String model, double paymentPrice) async {
    print('RIDER: Creating request document for driver ${driver.uid}');
    
    GeoFirePoint destination = locationService.getCurrentGeoFirePoint();
    GeoFirePoint pickup = locationService.getCurrentGeoFirePoint();
    
    Map<String, dynamic> destinationData = {
      'geopoint': destination.data['geopoint'],
      'geohash': destination.data['geohash']
    };

    Map<String, dynamic> pickupData = {
      'geopoint': pickup.data['geopoint'],
      'geohash': pickup.data['geohash']
    };

    String pAmount = paymentPrice.toString();
    String requestPath = 'drivers/${driver.uid}/requests/$rideID';
    
    print('RIDER: Writing to: $requestPath');

    await _firestore
        .collection('drivers')
        .doc(driver.uid)
        .collection('requests')
        .doc(rideID)
        .set(Request(
                id: rideID as String,
                name: userService.user.firstName,
                destinationAddress: destinationData,
                pickupAddress: pickupData,
                price: "\$$pAmount",
                photoURL: userService.user.profilePictureURL,
                model: model,
                timeout: Timestamp.fromMillisecondsSinceEpoch(
                    Timestamp.now().millisecondsSinceEpoch + 60000))
            .toJson());

    print('RIDER: Request document created, waiting for response...');

    int iterations = 0;
    while (!goToNextDriver) {
      await Future.delayed(const Duration(seconds: 1));
      iterations++;
      if (iterations >= 70) {
        print('RIDER: Request timeout after 70 seconds');
        goToNextDriver = true;
        return Future.value(false);
      }
    }
    goToNextDriver = false;
    return Future.value(true);
  }

  void _retrievePickupRadius() async {
    DocumentReference adminSettingsRef =
        _firestore.collection('config_settings').doc('admin_settings');
    pickupRadius =
        (await adminSettingsRef.get()).get('PickupRadius').toDouble();
  }

  // This method is attached to the ride stream and run every time the ride document in firestore changes.
  // Use it to keep the UI state in sync and the local Ride object updated.
  void _onRideUpdate(Ride updatedRide) {
    if (updatedRide.uid != userService.userID)
      return;
    ride = updatedRide;
    switch (updatedRide.status) {
      case 'CANCELED':
        removeRide = true;
        isSearchingForRide = false;
        cancelRide();
        break;
      case 'IN_PROGRESS':
        isSearchingForRide = false;
        goToNextDriver = true;
        break;
      case 'INITIALIZING':
        break;
      case 'SEARCHING':
        goToNextDriver = true;
        break;
      case 'WAITING':
        break;
      case 'ENDED':
        removeRide = true;
        isSearchingForRide = false;
        goToNextDriver = false;
        endRide();
        removeCurrentRider();
        break;
      default:
    }
  }

  Future<void> _initializeRideInFirestore(
      double lat, double long, double paymentPrice) async {
    GeoFirePoint destination = GeoFirePoint(lat, long);
    GeoFirePoint pickup = locationService.getCurrentGeoFirePoint();
    DocumentSnapshot myRide = await rideReference.get();
    
    // Add to current rides counter (only once)
    addCurrentRider();
    
    if (!myRide.exists) {
      print('Creating new ride document');
      await rideReference.set({
        'uid': userService.userID,
        'userName': userService.user.firstName,
        'userPhotoURL': userService.user.profilePictureURL,
        'drid': '',
        'lastActivity': DateTime.now(),
        'pickupAddress': pickup.data,
        'destinationAddress': destination.data,
        'status': "INITIALIZING",
        'startTime': Timestamp.now(),
        'endTime': Timestamp.now(),
        'price': paymentPrice,
      });
    } else {
      print('Updating existing ride document');
      await rideReference.set({
        'uid': userService.userID,
        'userName': userService.user.firstName,
        'userPhotoURL': userService.user.profilePictureURL,
        'drid': '',
        'lastActivity': DateTime.now(),
        'pickupAddress': pickup.data,
        'destinationAddress': destination.data,
        'status': "INITIALIZING",
        'price': paymentPrice,
      }, SetOptions(merge: true));
    }
  }

  Future<void> addCurrentRider() async {
    // Use atomic increment to prevent race conditions
    await currentRidesReference.set({
      'ridesGoingNow': FieldValue.increment(1)
    }, SetOptions(merge: true));
  }

  Future<void> removeCurrentRider() async {
    // Use atomic decrement to prevent race conditions
    await currentRidesReference.set({
      'ridesGoingNow': FieldValue.increment(-1)
    }, SetOptions(merge: true));
  }

  Stream<Ride> getRideStream() {
    return rideReference.snapshots().map((snapshot) {
      return Ride.fromDocument(snapshot);
    });
  }

  Stream<QuerySnapshot> getRiderHistory() {
    var firebaseUser = auth.FirebaseAuth.instance.currentUser;
    CollectionReference paymentsMethods = FirebaseFirestore.instance
        .collection('rides')
        .doc(firebaseUser?.uid)
        .collection('payments');
    return paymentsMethods.snapshots();
  }

  Future<Ride?> fetchRide(String rideID) async {
    try {
      DocumentSnapshot rideDoc =
          await _firestore.collection('rides').doc(rideID).get();
      if (rideDoc.exists) {
        return Ride.fromDocument(rideDoc);
      }
    } catch (e) {
      print("Error fetching ride: $e");
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchRideDestination(String rideID) async {
    try {
      DocumentSnapshot rideDoc =
          await _firestore.collection('rides').doc(rideID).get();
      dynamic destinationAddress = rideDoc.get('destinationAddress');
      return {
        'geopoint': destinationAddress['geopoint'],
        'geohash': destinationAddress['geohash']
      };
    } catch (e) {
      print("Error fetching ride: $e");
      return null;
    }
  }
}