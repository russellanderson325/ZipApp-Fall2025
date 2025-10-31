/*
 * ride.dart
 * This file contains the RideService class which is responsible for managing the user's ride.
 */
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zipapp/business/drivers.dart';
import 'package:zipapp/business/location.dart';
import 'package:zipapp/business/user.dart';
import 'package:zipapp/models/driver.dart';
import 'package:zipapp/models/request.dart';
import 'package:zipapp/models/rides.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:zipapp/logger.dart';

class RideService {
  final logger = AppLogger();
  
  static final RideService _instance = RideService._internal();
  final bool showDebugPrints = true;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late DocumentReference rideReference;
  late DocumentReference currentRidesReference;
  bool isSearchingForRide = false;
  bool goToNextDriver = false;
  late Stream<Ride> rideStream;
  StreamSubscription? rideSubscription;
  Ride? ride;
  bool removeRide = false;
  double pickupRadius = 5.0;
  String? rideID;
  Driver? acceptedDriver;
  bool _isRideInProgress = false;
  bool _hasIncrementedCounter = false;
  
  // Services
  LocationService locationService = LocationService();
  DriverService driverService = DriverService();
  UserService userService = UserService();
  // Subscriptions
  late Stream<List<DocumentSnapshot>> nearbyDrivers;

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
  RideService._internal() { currentRidesReference =
        _firestore.collection('CurrentRides').doc('currentRides');
    
    // Check if user has an active ride
    if (userService.user.currentRideId != "" && userService.user.isRiding) {
      rideID = userService.user.currentRideId;
      rideReference = _firestore.collection('rides').doc(rideID);
      if (showDebugPrints) {
        logger.info('RideService: Initialized with existing ride ID: $rideID');
      }
    } else {
      rideReference = _firestore.collection('rides').doc();
      if (showDebugPrints) {
        logger.info('RideService: Initialized without active ride');
      }
    }
  }

  void initializeRideWithoutID() async {
    if (showDebugPrints) {
      logger.info('RideService: Initializing new ride document');
    }
    
    if (rideID == null || rideID!.isEmpty) {
      rideReference = _firestore.collection('rides').doc();
      rideID = rideReference.id;
      if (showDebugPrints) {
        logger.info('RideService: Created new ride ID: $rideID');
      }
    } else {
      if (showDebugPrints) {
        logger.info('RideService: Using existing ride ID: $rideID');
      }
    }
    
    currentRidesReference =
        _firestore.collection('CurrentRides').doc('currentRides');
    
    // Check if ride document exists
    try {
      DocumentSnapshot snapshot = await rideReference.get();
      if (snapshot.exists) {
        ride = Ride.fromDocument(snapshot);
        if (showDebugPrints) {
          logger.info('RideService: Loaded existing ride with status: ${ride?.status}');
        }
      } else {
        if (showDebugPrints) {
          logger.info('RideService: No existing ride document found');
        }
      }
    } catch (e) {
      if (showDebugPrints) {
        logger.error('RideService: Error loading ride: $e');
      }
    }
    
    setupService();
  }
  
  /// Check if service needs initialization before starting a ride
  Future<void> ensureInitialized() async {
    if (rideID == null || rideID!.isEmpty) {
      if (showDebugPrints) {
        logger.info('RideService: Service not initialized, initializing now...');
      }
      initializeRideWithoutID();
    }
  }

  bool hasActiveDriverConnection() {
    return rideID != null && 
           acceptedDriver != null && 
           ride?.status == "IN_PROGRESS";
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
      logger.info("Directions updated: $newDirections");
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
      'rideStatus': ride?.status ?? 'UNKNOWN',
      'isConnected': hasActiveDriverConnection(),
      'driverName': acceptedDriver?.firstName ?? 'No driver assigned',
    };
  }

  Future<void> startRide(
      double lat, double long, double paymentPrice, String model) async {
    
    // Prevent multiple simultaneous rides
    if (_isRideInProgress) {
      throw Exception('A ride is already in progress');
    }
    
    _isRideInProgress = true;
    _hasIncrementedCounter = false;
    
    try {
      logger.info('RIDER: ===== STARTING RIDE REQUEST =====');
      logger.info('RIDER: Destination: $lat, $long');
      logger.info('RIDER: Price: \$${paymentPrice.toStringAsFixed(2)}');
      logger.info('RIDER: Model requested: $model');
      
      await ensureInitialized();
      
      bool locationAvailable = await locationService.isLocationAvailable();
      if (!locationAvailable) {
        throw Exception('Location services not available. Please enable GPS and grant location permissions.');
      }
      
      logger.info('RIDER: Getting current location...');
      await locationService.getCurrentPosition();
      
      await _initializeRideInFirestore(lat, long, paymentPrice);
      logger.info('RIDER: Ride initialized in Firestore (ID: $rideID)');
      
      rideStream = rideReference
          .snapshots()
          .map((snapshot) => Ride.fromDocument(snapshot))
          .asBroadcastStream();
      rideSubscription = rideStream.listen(_onRideUpdate);
      
      int timesSearched = 0;
      double radius = 1;
      isSearchingForRide = true;

      logger.info('RIDER: ===== STARTING DRIVER SEARCH =====');

      while (isSearchingForRide) {
        logger.info('RIDER: Search iteration ${timesSearched + 1}');
        logger.info('RIDER: Searching with radius: $radius miles');

        List<Driver> nearbyDrivers =
            await driverService.getNearbyDriversListWithModel(radius, model);

        logger.info('RIDER: Found ${nearbyDrivers.length} nearby drivers');

        if (nearbyDrivers.isNotEmpty && timesSearched < 6) {
          Position riderPosition = await locationService.getCurrentPosition();
          
          // Filter out drivers without valid location data
          nearbyDrivers = nearbyDrivers.where((driver) {
            return driver.geoFirePoint != null;
          }).toList();
          
          if (nearbyDrivers.isEmpty) {
            logger.info('RIDER: No drivers with valid location data');
            timesSearched += 1;
            continue;
          }
          
          nearbyDrivers.sort((a, b) {
            double distanceA = _calculateDistance(
              riderPosition.latitude,
              riderPosition.longitude,
              a.geoFirePoint!.latitude,
              a.geoFirePoint!.longitude,
            );
            double distanceB = _calculateDistance(
              riderPosition.latitude,
              riderPosition.longitude,
              b.geoFirePoint!.latitude,
              b.geoFirePoint!.longitude,
            );
            return distanceA.compareTo(distanceB);
          });

          logger.info('RIDER: ========================================');
          logger.info('RIDER: Sorted ${nearbyDrivers.length} drivers by distance:');
          for (int i = 0; i < nearbyDrivers.length; i++) {
            Driver d = nearbyDrivers[i];
            double dist = _calculateDistance(
              riderPosition.latitude,
              riderPosition.longitude,
              d.geoFirePoint!.latitude,
              d.geoFirePoint!.longitude,
            );
            logger.info('  #${i + 1}: ${d.firstName} ${d.lastName} - ${dist.toStringAsFixed(3)} miles');
          }
          logger.info('RIDER: ========================================');

          // Set status to WAITING before trying drivers
          await rideReference.update({'status': 'WAITING'});
          
          // Try each driver until one accepts
          bool foundDriver = false;
          for (int i = 0; i < nearbyDrivers.length && !foundDriver; i++) {
            if (!isSearchingForRide) break;
            
            Driver driver = nearbyDrivers[i];
            double driverDistance = _calculateDistance(
              riderPosition.latitude,
              riderPosition.longitude,
              driver.geoFirePoint!.latitude,
              driver.geoFirePoint!.longitude,
            );

            logger.info('RIDER: ========================================');
            logger.info('RIDER: Sending request to driver ${i + 1}/${nearbyDrivers.length}');
            logger.info('  - Name: ${driver.firstName} ${driver.lastName}');
            logger.info('  - UID: ${driver.uid}');
            logger.info('  - Model: ${driver.cartModel}');
            logger.info('  - Distance: ${driverDistance.toStringAsFixed(2)} miles');
            logger.info('  - Rank: #${i + 1} (closest first)');
            logger.info('RIDER: ========================================');

            bool driverAccepted =
                await _sendRequestToDriver(driver, model, paymentPrice);
            
            if (driverAccepted) {
              logger.info('RIDER:  DRIVER ACCEPTED! ');
              logger.info('  - Accepted driver: ${driver.firstName} ${driver.lastName}');
              logger.info('  - Distance: ${driverDistance.toStringAsFixed(2)} miles');
              logger.info('  - Was ranked: #${i + 1} of ${nearbyDrivers.length}');
              acceptedDriver = driver;
              foundDriver = true;
              isSearchingForRide = false;
              break;
            } else {
              logger.info('RIDER: Driver ${i + 1} did not accept');
              logger.info('  - Continuing to next driver in list...');
            }
          }
          
          if (!foundDriver) {
            logger.info('RIDER: No drivers accepted in this iteration');
          }
          
          timesSearched += 1;
        } else {
          logger.info('RIDER: No drivers found, expanding search radius');
          timesSearched += 1;
          radius += 10;
          if (timesSearched > 5) {
            logger.info('RIDER: Max search attempts reached, giving up');
            isSearchingForRide = false;
          } else {
            logger.info('RIDER: Waiting 60 seconds before next search...');
            await Future.delayed(const Duration(seconds: 60));
          }
        }
      }

      logger.info('RIDER: ===== SEARCH COMPLETE =====');

      if (ride?.status == "IN_PROGRESS") {
        logger.info('RIDER: Ride is in progress!');
      } else if (!isSearchingForRide && ride?.status != "IN_PROGRESS") {
        logger.info('RIDER: Search ended - no driver accepted after all attempts');
        logger.info('RIDER: Canceling ride');
        await rideReference.update({
          'lastActivity': DateTime.now(), 
          'status': "CANCELED"
        });
        // Decrement counter when no driver found
        if (_hasIncrementedCounter) {
          await removeCurrentRider();
          _hasIncrementedCounter = false;
        }
      }
    } catch (e) {
      logger.info('RIDER: Error during ride search: $e');
      // Ensure cleanup on error
      if (_hasIncrementedCounter) {
        await removeCurrentRider();
        _hasIncrementedCounter = false;
      }
      rethrow;
    } finally {
      _isRideInProgress = false;
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
      rideSubscription?.cancel();
    } catch (e) {
      logger.info('Error canceling subscription: $e');
    }
    
    try {
      DocumentSnapshot myRide = await rideReference.get();
      if (acceptedDriver != null) {
        _getDriverReference(acceptedDriver!.uid)
            .collection('requests')
            .doc(rideID)
            .delete();
      }
      if (myRide.exists) {
        if (_hasIncrementedCounter) {
          await removeCurrentRider();
          _hasIncrementedCounter = false;
        }
        await rideReference.update({
          'lastActivity': DateTime.now(),
          'status': "CANCELED",
        });
        // reset rideReference
        rideReference = _firestore.collection('rides').doc();
        rideID = null;
        acceptedDriver = null;
      }
    } catch (e) {
      logger.info('Error in cancelRide: $e');
    }
  }

  void endRide() async {
    try {
      rideSubscription?.cancel();
      await rideReference.update({
        'lastActivity': DateTime.now(),
        'status': "ENDED",
      });
      rideReference = _firestore.collection('rides').doc();
      rideID = null;
      acceptedDriver = null;
    } catch (e) {
      logger.info('Error in endRide: $e');
    }
  }

  _getDriverReference(String driverID) {
    return _firestore.collection('drivers').doc(driverID);
  }

  Future<bool> _sendRequestToDriver(
      Driver driver, String model, double paymentPrice) async {
    logger.info('RIDER: Creating request document for driver ${driver.uid}');

    goToNextDriver = false;
    
    GeoFirePoint destination = await locationService.getCurrentGeoFirePointAsync();
    GeoFirePoint pickup = await locationService.getCurrentGeoFirePointAsync();
    
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

    logger.info('RIDER: Writing to: $requestPath');
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
                    Timestamp.now().millisecondsSinceEpoch + 10000))
            .toJson());

    logger.info('RIDER: Request document created, waiting for response...');

    int iterations = 0;
    String? statusBeforeWait = ride?.status;
    
    while (isSearchingForRide && iterations < 15) {
      await Future.delayed(const Duration(seconds: 1));
      iterations++;
      
      if (ride?.status == "IN_PROGRESS") {
        logger.info('RIDER: Driver ACCEPTED (status changed to IN_PROGRESS)');
        return true;
      } else if (ride?.status == "SEARCHING" && ride?.status != statusBeforeWait) {
        logger.info('RIDER: Driver DECLINED (status changed to SEARCHING)');
        return false;
      }
    }

    logger.info('RIDER: Driver TIMEOUT (no response after 15 seconds)');
    return false;
  }

  void _retrievePickupRadius() async {
    DocumentReference adminSettingsRef =
        _firestore.collection('config_settings').doc('admin_settings');
    pickupRadius =
        (await adminSettingsRef.get()).get('PickupRadius').toDouble();
  }

  /// Calculate distance between two points in miles using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusMiles = 3958.8;
    
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * 
        math.cos(_degreesToRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadiusMiles * c;
  }
  
  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  void _onRideUpdate(Ride updatedRide) {
    logger.info('RIDER: ========================================');
    logger.info('RIDER: _onRideUpdate called');
    logger.info('  - New status: ${updatedRide.status}');
    logger.info('  - Old status: ${ride?.status ?? "null"}');
    logger.info('  - isSearchingForRide: $isSearchingForRide');
    logger.info('RIDER: ========================================');
    
    if (updatedRide.uid != userService.userID) {
      logger.info('RIDER: Ride UID mismatch, ignoring update');
      return;
    }
    
    ride = updatedRide;
    
    switch (updatedRide.status) {
      case 'CANCELED':
        logger.info('RIDER: Ride status changed to CANCELED');
        removeRide = true;
        isSearchingForRide = false;
        goToNextDriver = true;
        break;
      case 'IN_PROGRESS':
        logger.info('RIDER: Status changed to IN_PROGRESS (driver accepted!)');
        isSearchingForRide = false;
        break;
      case 'INITIALIZING':
        logger.info('RIDER: Ride status is INITIALIZING');
        break;
      case 'SEARCHING':
        logger.info('RIDER: Status changed to SEARCHING (driver declined)');
        break;
      case 'WAITING':
        logger.info('RIDER: Ride status is WAITING');
        break;
      case 'ENDED':
        logger.info('RIDER: Ride status changed to ENDED');
        removeRide = true;
        isSearchingForRide = false;
        goToNextDriver = false;
        endRide();
        if (_hasIncrementedCounter) {
          removeCurrentRider();
          _hasIncrementedCounter = false;
        }
        break;
      default:
        logger.info('RIDER: Unknown ride status: ${updatedRide.status}');
    }
  }

  Future<void> _initializeRideInFirestore(
      double lat, double long, double paymentPrice) async {
    GeoFirePoint destination = GeoFirePoint(lat, long);
    GeoFirePoint pickup = await locationService.getCurrentGeoFirePointAsync();
    DocumentSnapshot myRide = await rideReference.get();
    
    // Add to current rides counter (only once)
    if (!_hasIncrementedCounter) {
      await addCurrentRider();
      _hasIncrementedCounter = true;
    }
    
    if (!myRide.exists) {
      logger.info('Creating new ride document');
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
      logger.info('Updating existing ride document');
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
    await currentRidesReference.set({
      'ridesGoingNow': FieldValue.increment(1)
    }, SetOptions(merge: true));
    logger.info('RIDER: Incremented ridesGoingNow counter');
  }

  Future<void> removeCurrentRider() async {
    await currentRidesReference.set({
      'ridesGoingNow': FieldValue.increment(-1)
    }, SetOptions(merge: true));
    logger.info('RIDER: Decremented ridesGoingNow counter');
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
      logger.info("Error fetching ride: $e");
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
      logger.info("Error fetching ride: $e");
      return null;
    }
  }
}