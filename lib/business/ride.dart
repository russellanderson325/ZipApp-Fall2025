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

class RideService {
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
    currentRidesReference =
        _firestore.collection('CurrentRides').doc('currentRides');
    
    // Check if user has an active ride
    if (userService.user.currentRideId != "" && userService.user.isRiding) {
      rideID = userService.user.currentRideId;
      rideReference = _firestore.collection('rides').doc(rideID);
      if (showDebugPrints) {
        print('RideService: Initialized with existing ride ID: $rideID');
      }
    } else {
      // Create a reference but don't log yet - will be set when ride starts
      rideReference = _firestore.collection('rides').doc();
      if (showDebugPrints) {
        print('RideService: Initialized without active ride');
      }
    }
  }

  /// Initialize a new ride reference (called when starting a new ride)
  void initializeRideWithoutID() async {
    if (showDebugPrints) {
      print('RideService: Initializing new ride document');
    }
    
    // Only create new reference if we don't already have a valid ride
    if (rideID == null || rideID!.isEmpty) {
      rideReference = _firestore.collection('rides').doc();
      rideID = rideReference.id;
      if (showDebugPrints) {
        print('RideService: Created new ride ID: $rideID');
      }
    } else {
      if (showDebugPrints) {
        print('RideService: Using existing ride ID: $rideID');
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
          print('RideService: Loaded existing ride with status: ${ride?.status}');
        }
      } else {
        if (showDebugPrints) {
          print('RideService: No existing ride document found');
        }
      }
    } catch (e) {
      if (showDebugPrints) {
        print('RideService: Error loading ride: $e');
      }
    }
    
    setupService();
  }
  
  /// Check if service needs initialization before starting a ride
  Future<void> ensureInitialized() async {
    if (rideID == null || rideID!.isEmpty) {
      if (showDebugPrints) {
        print('RideService: Service not initialized, initializing now...');
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
      print('RIDER: ===== STARTING RIDE REQUEST =====');
      print('RIDER: Destination: $lat, $long');
      print('RIDER: Price: \$${paymentPrice.toStringAsFixed(2)}');
      print('RIDER: Model requested: $model');
      
      // ✅ Ensure service is initialized
      await ensureInitialized();
      
      // ✅ Check location availability first
      bool locationAvailable = await locationService.isLocationAvailable();
      if (!locationAvailable) {
        throw Exception('Location services not available. Please enable GPS and grant location permissions.');
      }
      
      // ✅ Get current position before starting ride
      print('RIDER: Getting current location...');
      await locationService.getCurrentPosition();
      print('RIDER: ✓ Location acquired');
      
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
          // ✅ Sort drivers by distance (closest first)
          Position riderPosition = await locationService.getCurrentPosition();
          
          // Filter out drivers without valid location data
          nearbyDrivers = nearbyDrivers.where((driver) {
            return driver.geoFirePoint != null;
          }).toList();
          
          if (nearbyDrivers.isEmpty) {
            print('RIDER: No drivers with valid location data');
            timesSearched += 1;
            continue;
          }
          
          nearbyDrivers.sort((a, b) {
            // geoFirePoint is a GeoFirePoint object, not a Map
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
          
          print('RIDER: Sorted ${nearbyDrivers.length} drivers by distance');
          
          // ✅ Try each driver until one accepts
          bool foundDriver = false;
          for (int i = 0; i < nearbyDrivers.length && !foundDriver; i++) {
            if (!isSearchingForRide) break; // Check if search was canceled
            
            Driver driver = nearbyDrivers[i];
            double driverDistance = _calculateDistance(
              riderPosition.latitude,
              riderPosition.longitude,
              driver.geoFirePoint!.latitude,
              driver.geoFirePoint!.longitude,
            );
            
            print('RIDER: Sending request to driver ${i + 1}/${nearbyDrivers.length}');
            print('  - Name: ${driver.firstName} ${driver.lastName}');
            print('  - UID: ${driver.uid}');
            print('  - Model: ${driver.cartModel}');
            print('  - Distance: ${driverDistance.toStringAsFixed(2)} miles');
            
            await rideReference.update({'status': 'WAITING'});
            bool driverAccepted =
                await _sendRequestToDriver(driver, model, paymentPrice);
            
            if (driverAccepted) {
              print('RIDER: ✓ Driver accepted the ride!');
              acceptedDriver = driver;
              foundDriver = true;
              isSearchingForRide = false; // ✅ Stop searching
              break; // ✅ Exit the loop
            } else {
              print('RIDER: Driver did not accept (timeout or declined)');
              // Continue to next driver
            }
          }
          
          if (!foundDriver) {
            print('RIDER: No drivers accepted in this iteration');
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
      
      if (ride?.status == "IN_PROGRESS") {
        print('RIDER: Ride is in progress!');
      } else {
        print('RIDER: No driver found, canceling ride');
        await rideReference.update({
          'lastActivity': DateTime.now(), 
          'status': "CANCELED"
        });
        // ✅ Decrement counter when no driver found
        if (_hasIncrementedCounter) {
          await removeCurrentRider();
          _hasIncrementedCounter = false;
        }
      }
    } catch (e) {
      print('RIDER: Error during ride search: $e');
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
      print('Error canceling subscription: $e');
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
      print('Error in cancelRide: $e');
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
      print('Error in endRide: $e');
    }
  }

  _getDriverReference(String driverID) {
    return _firestore.collection('drivers').doc(driverID);
  }

  Future<bool> _sendRequestToDriver(
      Driver driver, String model, double paymentPrice) async {
    print('RIDER: Creating request document for driver ${driver.uid}');
    
    // ✅ Use async version to get GeoFirePoint
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
    while (!goToNextDriver && isSearchingForRide) {
      await Future.delayed(const Duration(seconds: 1));
      iterations++;
      if (iterations >= 10) {
        print('RIDER: Request timeout after 10 seconds');
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

  /// Calculate distance between two points in miles using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusMiles = 3958.8; // Earth's radius in miles
    
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

  // This method is attached to the ride stream and run every time the ride document in firestore changes.
  // Use it to keep the UI state in sync and the local Ride object updated.
  void _onRideUpdate(Ride updatedRide) {
    print('RIDER: _onRideUpdate called with status: ${updatedRide.status}');
    
    if (updatedRide.uid != userService.userID) {
      print('RIDER: Ride UID mismatch, ignoring update');
      return;
    }
    
    ride = updatedRide;
    
    switch (updatedRide.status) {
      case 'CANCELED':
        print('RIDER: Ride status changed to CANCELED');
        removeRide = true;
        isSearchingForRide = false;
        // Don't call cancelRide() here - it would create a loop
        // Just set the flags to stop searching
        goToNextDriver = true;
        break;
      case 'IN_PROGRESS':
        print('RIDER: Ride status changed to IN_PROGRESS');
        isSearchingForRide = false;
        goToNextDriver = true;
        break;
      case 'INITIALIZING':
        print('RIDER: Ride status is INITIALIZING');
        break;
      case 'SEARCHING':
        print('RIDER: Ride status changed to SEARCHING');
        goToNextDriver = true;
        break;
      case 'WAITING':
        print('RIDER: Ride status is WAITING');
        break;
      case 'ENDED':
        print('RIDER: Ride status changed to ENDED');
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
        print('RIDER: Unknown ride status: ${updatedRide.status}');
    }
  }

  Future<void> _initializeRideInFirestore(
      double lat, double long, double paymentPrice) async {
    GeoFirePoint destination = GeoFirePoint(lat, long);
    // ✅ Use async version to get pickup location
    GeoFirePoint pickup = await locationService.getCurrentGeoFirePointAsync();
    DocumentSnapshot myRide = await rideReference.get();
    
    // Add to current rides counter (only once)
    if (!_hasIncrementedCounter) {
      await addCurrentRider();
      _hasIncrementedCounter = true;
    }
    
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
    print('RIDER: Incremented ridesGoingNow counter');
  }

  Future<void> removeCurrentRider() async {
    // Use atomic decrement to prevent race conditions
    await currentRidesReference.set({
      'ridesGoingNow': FieldValue.increment(-1)
    }, SetOptions(merge: true));
    print('RIDER: Decremented ridesGoingNow counter');
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