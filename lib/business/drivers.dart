/*
 * drivers.dart
 * This file contains the driver service class which is responsible for handling all driver related operations.
 */
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zipapp/business/location.dart';
import 'package:zipapp/business/user.dart';
import 'package:zipapp/models/driver.dart';
import 'package:zipapp/models/request.dart';
import 'package:zipapp/models/rides.dart';
import 'package:zipapp/services/payment.dart';
import 'package:intl/intl.dart';
import 'package:zipapp/logger.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

class DriverService {
  final logger = AppLogger();

  static final DriverService _instance = DriverService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final bool showDebugPrints = true;
  GeoFlutterFire geo = GeoFlutterFire();
  LocationService locationService = LocationService();
  late StreamSubscription<Position> locationSub;
  late CollectionReference driversCollection;
  late DocumentReference driverReference;
  late CollectionReference shiftCollection;
  late DocumentReference shiftReference;
  UserService userService = UserService();
  late List<Driver> nearbyDriversList;
  late Stream<List<Driver>> nearbyDriversListStream;
  late GeoFirePoint myLocation;
  late Driver driver;
  late CurrentShift currentShift;
  StreamSubscription<Driver>? driverSub;
  // Request specific variables
  late CollectionReference requestCollection;
  late Stream<List<Request>> requestStream;
  StreamSubscription<List<Request>>? requestSub;
  late List<Request> currentRequests = [];
  Request? currentRequest;
  bool _isCurrentRideInitialized = false;
  // Ride specific varaibles
  late Stream<Ride> rideStream;
  StreamSubscription<Ride>? rideSub;
  late Ride currentRide;
  //Shift specific variables
  late String shiftuid;
  int requestLength = 0;
  bool isDriving = false;

  //  Timer and tracking for auto-decline
  Timer? _autoDeclineTimer;
  String? _currentRequestId;

  // Add callback for UI to listen to incoming requests
  Function(Request)? onRequestReceived;
  Function(String)? onRequestTimeout;

  // Function? uiCallbackFunction;

  HttpsCallable driverClockInFunction =
      FirebaseFunctions.instance.httpsCallable(
    'driverClockIn',
  );

  HttpsCallable driverClockOutFunction =
      FirebaseFunctions.instance.httpsCallable(
    'driverClockOut',
  );

  HttpsCallable driverStartBreakFunction =
      FirebaseFunctions.instance.httpsCallable(
    'driverStartBreak',
  );

  HttpsCallable driverEndBreakFunction =
      FirebaseFunctions.instance.httpsCallable(
    'driverEndBreak',
  );

  factory DriverService() {
    return _instance;
  }

  // TODO: Update to use user.isDriver before initializing since only driver users will need the service.

  DriverService._internal() {
    driversCollection = _firestore.collection('drivers');
    driverReference = driversCollection.doc(userService.userID);
    requestCollection = driverReference.collection('requests');
    shiftCollection = driverReference.collection('shifts');
    shiftuid = DateFormat('MMddyyyy').format(DateTime.now());
  }

  /*
   * Setup the driver service, this will setup the driver service and listen for requests.
   * @return Future<bool> True if the driver service was setup successfully, false otherwise
   */
  Future<bool> setupService() async {
    logger.info('DRIVER: ===== SETTING UP DRIVER SERVICE =====');
    await _updateDriverRecord();

    logger.info('DRIVER: Setting up document listener');
    driverSub = driverReference
        .snapshots(includeMetadataChanges: true)
        .map((DocumentSnapshot snapshot) {
      Driver driver = Driver.fromDocument(snapshot);
      logger.info('DRIVER: Document snapshot received');
      logger.info('  - isWorking: ${driver.isWorking}');
      logger.info('  - isAvailable: ${driver.isAvailable}');
      logger.info('  - currentRideID: ${driver.currentRideID}');

      if (driver.currentRideID.isNotEmpty) {
        setupRideStream(driver.currentRideID);
      }
      return driver;
    }).listen((driver) {
      this.driver = driver;
      handleDriverAvailability(driver);
    });

    logger.info('DRIVER: Setting up location listener');
    locationSub = locationService.positionStream.listen(_updatePosition);

    logger.info('DRIVER: ===== DRIVER SERVICE SETUP COMPLETE =====');
    return true;
  }

  /*
   * Set callback functions for UI to listen to request events
   * @param onRequest Callback when a new request is received
   * @param onTimeout Callback when a request times out
   */
  void setRequestCallbacks({
    Function(Request)? onRequest,
    Function(String)? onTimeout,
  }) {
    onRequestReceived = onRequest;
    onRequestTimeout = onTimeout;
  }

  void handleDriverAvailability(Driver driver) {
    logger.info('DRIVER: Checking availability');
    logger.info('  - isWorking: ${driver.isWorking}');
    logger.info('  - isAvailable: ${driver.isAvailable}');
    logger.info('  - isDriving: $isDriving');

    if (driver.isWorking && driver.isAvailable && !isDriving) {
      logger.info('DRIVER: Conditions met! Starting to drive...');
      startDriving();
    } else {
      logger.info('DRIVER: Not starting - conditions not met');
    }
  }

  void setupRideStream(String rideId) {
    if (rideSub != null) {
      rideSub?.cancel();
    }
    DocumentReference rideRef = _firestore.collection('rides').doc(rideId);
    rideStream =
        rideRef.snapshots().map((snapshot) => Ride.fromDocument(snapshot));
    rideSub = rideStream.listen((ride) {
      _onRideUpdate(ride);
    });
  }

  /*
   * Get the driver's current state (isAvailable, isWorking, isOnBreak)
   * @return Map<String, bool> The driver's current state
   */
  Future<Map<String, bool>> getDriverStates() async {
    DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(userService.userID)
        .get();

    Map<String, bool> driverStates = {
      'isAvailable': documentSnapshot.get('isAvailable') ?? false,
      'isWorking': documentSnapshot.get('isWorking') ?? false,
      'isOnBreak': documentSnapshot.get('isOnBreak') ?? false
    };

    logger.info('DEBUG Driver States: $driverStates');
    return driverStates;
  }

  /*
   * Update the driver's position
   * @param pos The position to update the driver's position to
   * @return void
   */
  void _updatePosition(Position pos) {
    if (driver.isWorking) {
      myLocation = geo.point(latitude: pos.latitude, longitude: pos.longitude);
      // TODO: Check for splitting driver and position into seperate documents in firebase as an optimization
      driverReference.update(
          {'lastActivity': DateTime.now(), 'geoFirePoint': myLocation.data});
    }
  }

  /*
   * Start the driver service, this will start the driver service and listen for requests.
   * The callback function will be called when the driver service is started.
   * @return void
   */
  void startDriving() async {
    logger.info('DRIVER: ===== STARTING DRIVING MODE =====');
    isDriving = true;

    var geoPoint = locationService.getCurrentGeoFirePoint();
    logger.info(
        'DRIVER: Current location: ${geoPoint.latitude}, ${geoPoint.longitude}');
    // Clean up any stale requests before starting
    logger.info('DRIVER: Cleaning up old requests...');
    try {
      QuerySnapshot oldRequests = await requestCollection.get();
      int deletedCount = 0;
      for (var doc in oldRequests.docs) {
        await doc.reference.delete();
        deletedCount++;
      }
      logger.info('DRIVER: Cleared $deletedCount old requests');
    } catch (e) {
      logger.error('DRIVER: Error cleaning requests: $e');
    }

    // Reset request counter
    requestLength = 0;

    await driverReference.update({
      'lastActivity': DateTime.now(),
      'geoFirePoint': geoPoint.data,
      'isAvailable': true,
    });

    logger.info('DRIVER: Updated Firestore document');
    logger.info('DRIVER: Initializing request listener...');

    // if (_isRequestSubListening) return;
    initRequestSub();
    await Future.delayed(const Duration(milliseconds: 1000));

    logger.info(
        'DRIVER: ===== DRIVING MODE ACTIVE - LISTENING FOR REQUESTS =====');
  }

  void initRequestSub() {
    // If requestSub is not already listening, start listening
    if (requestSub != null) {
      logger.info('DRIVER: Request listener already active');
      return;
    }

    String requestPath = 'drivers/${userService.userID}/requests';
    logger.info('DRIVER: Starting request listener at: $requestPath');

    requestStream = requestCollection.snapshots().map((event) {
      logger.info(
          'DRIVER: Request snapshot received - ${event.docs.length} documents');
      return event.docs.map((e) => Request.fromDocument(e)).toList();
    }).asBroadcastStream();

    requestSub = requestStream.listen((List<Request> requests) {
      logger.info(
          'DRIVER: Request listener triggered - ${requests.length} requests');

      if (requestLength < requests.length) {
        requestLength = requests.length;
        // Handle the first request
        Request firstRequest = requests.last;
        logger.info('DRIVER: NEW REQUEST RECEIVED!');
        logger.info('  - From: ${firstRequest.name}');
        logger.info('  - Request ID: ${firstRequest.id}');
        logger.info('  - Price: ${firstRequest.price}');
        logger.info('  - Model: ${firstRequest.model}');
        _onRequestReceived(firstRequest);
      } else if (requestLength > requests.length) {
        requestLength = requests.length;
        logger.info('DRIVER: Request count decreased to $requestLength');
      } else {
        // Do nothing
      }
    });

    logger.info('DRIVER: Request listener successfully initialized');
  }

  /*
   * Handle a request with cancelable auto-decline timer
   * @param req The request that has been received
   * @return void
   */
  void _onRequestReceived(Request req) {
    logger.info('DRIVER: ========================================');
    logger.info('DRIVER: Processing request ${req.id}');

    // Cancel any existing timer
    _autoDeclineTimer?.cancel();

    currentRequest = req;
    _currentRequestId = req.id;

    // Notify UI that a request has been received
    if (onRequestReceived != null) {
      logger.info('DRIVER: Calling UI callback');
      onRequestReceived!(req);
    } else {
      logger.info('DRIVER: WARNING - No UI callback set!');
    }

    // Calculate timeout duration
    var seconds = (req.timeout.seconds - Timestamp.now().seconds);
    logger.info('DRIVER: Request will auto-decline in $seconds seconds');
    logger.info('DRIVER: ========================================');

    if (seconds > 0) {
      // Set up cancelable timer
      _autoDeclineTimer = Timer(Duration(seconds: seconds), () {
        logger.info('DRIVER: ========================================');
        logger
            .info('DRIVER: Auto-decline timer triggered for request ${req.id}');

        // Check if this request is still current
        if (_currentRequestId == req.id) {
          logger.info('DRIVER: Auto-declining request ${req.id}');

          // Notify UI that request timed out
          if (onRequestTimeout != null) {
            onRequestTimeout!(req.id);
          }

          // Decline the request
          declineRequest(req.id);

          // Clear current request
          _currentRequestId = null;
        } else {
          logger.info(
              'DRIVER: Request ${req.id} already handled, skipping auto-decline');
        }
        logger.info('DRIVER: ========================================');
      });
    } else {
      logger.info(
          'DRIVER: Request ${req.id} already expired, declining immediately');
      if (onRequestTimeout != null) {
        onRequestTimeout!(req.id);
      }
      declineRequest(req.id);
      _currentRequestId = null;
    }
  }

  /*
   * Accept a request - cancels auto-decline timer
   * @param requestID The ID of the request to accept
   * @return void
   */
  Future<void> acceptRequest(String requestID) async {
    logger.info('DRIVER: ========================================');
    logger.info('DRIVER: Accepting request $requestID');

    // Cancel auto-decline timer
    if (_autoDeclineTimer != null && _autoDeclineTimer!.isActive) {
      _autoDeclineTimer!.cancel();
      logger.info('DRIVER: ✓ Canceled auto-decline timer');
    }

    // Clear current request ID since we're accepting
    _currentRequestId = null;

    DocumentSnapshot requestRef =
        await _firestore.collection('rides').doc(requestID).get();

    if (!requestRef.exists) {
      logger.info('DRIVER: ERROR - Ride document not found!');
      logger.info('DRIVER: ========================================');
      return;
    }

    rideStream = _firestore
        .collection('rides')
        .doc(requestID)
        .snapshots()
        .map((event) => Ride.fromDocument(event));
    rideSub = rideStream.listen(_onRideUpdate);

    logger.info('DRIVER: Updating driver and ride documents');
    await driverReference
        .update({'isAvailable': false, 'currentRideID': requestID});
    await _firestore.collection('rides').doc(requestID).update({
      'status': "IN_PROGRESS",
      'drid': userService.userID,
      'driverName': userService.user.firstName,
      'driverPhotoURL': userService.user.profilePictureURL
    });
    await requestCollection.doc(requestID).delete();

    logger.info('DRIVER: Request accepted successfully!');
    logger.info('DRIVER: ========================================');
  }

  /*
   * Decline a request - cancels auto-decline timer
   * @param requestID The ID of the request to decline
   * @return void
   */
  Future<void> declineRequest(String requestID) async {
    logger.info('DRIVER: ========================================');
    logger.info('DRIVER: Declining request $requestID');

    // Cancel auto-decline timer if this is manual decline
    if (_currentRequestId == requestID &&
        _autoDeclineTimer != null &&
        _autoDeclineTimer!.isActive) {
      _autoDeclineTimer!.cancel();
      logger.info('DRIVER: ✓ Canceled auto-decline timer (manual decline)');
    }

    // Clear current request
    if (_currentRequestId == requestID) {
      _currentRequestId = null;
    }

    DocumentSnapshot requestRef = await requestCollection.doc(requestID).get();
    if (requestRef.exists) {
      logger.info('DRIVER: Request exists, updating ride status to SEARCHING');
      await _firestore
          .collection('rides')
          .doc(requestID)
          .update({'status': "SEARCHING"});
      await requestCollection.doc(requestID).delete();
      logger.info('DRIVER: Request declined successfully');
    } else {
      logger.info(
          'DRIVER: Request already deleted (may have been auto-declined)');
    }
    logger.info('DRIVER: ========================================');
  }

  /*
   * Get current pending request for UI display
   * @return Request? The current request or null if none
   */
  Request? getCurrentRequest() {
    return currentRequest;
  }

  /*
   * Check if driver has any pending requests
   * @return bool True if there are pending requests
   */
  bool hasPendingRequest() {
    return currentRequest != null;
  }

  /*
   * FIXED: Stop driving - cleanup timers
   */
  void stopDriving() {
    logger.info('DRIVER: ========================================');
    logger.info('DRIVER: Stopping driving mode');

    // Cancel any active auto-decline timer
    _autoDeclineTimer?.cancel();
    _currentRequestId = null;

    isDriving = false;
    driverReference.update({
      'lastActivity': DateTime.now(),
      'currentRideID': '',
      'isAvailable': false,
    });

    // Clear requests from the driver on Firebase
    driverReference.collection('requests').get().then((value) {
      for (var doc in value.docs) {
        doc.reference.delete();
      }
    });

    // Stop listening for requests
    requestSub?.cancel();
    driverSub?.cancel();
    rideSub?.cancel();

    logger.info('DRIVER: Stopped driving, all timers canceled');
    logger.info('DRIVER: ========================================');
  }

  void completeRide() async {
    if (currentRide.status != "ENDED") {
      String rideID = driver.currentRideID;
      _addRideToDriver(rideID);
      _addRideToRider(rideID);

      await _firestore.collection('rides').doc(driver.currentRideID).update({
        'lastActivity': DateTime.now(),
        'status': 'ENDED',
        'drid': driver.uid,
        'driverName': "${driver.firstName} ${driver.lastName}",
        'driverPhotoURL': driver.profilePictureURL
      });
    }
    // stopDriving();
  }

  /*
   * Add the ride to the driver's list of past drives
   * @param rideID The ID of the ride to add to the driver's past drives
   * @return void
   */
  void _addRideToDriver(rideID) async {
    var rideObj = await _firestore.collection('rides').doc(rideID).get();
    var rideDriver = rideObj.get('drid');

    var driverPastDrives =
        (await _firestore.collection('users').doc(rideDriver).get())
            .get('pastDrives');
    driverPastDrives.add(driver.currentRideID);
    await _firestore
        .collection('users')
        .doc(rideDriver)
        .update({'pastDrives': driverPastDrives});
  }

  /*
   * Add the ride to the rider's list of past rides
   * @param rideID The ID of the ride to add to the rider's past rides
   * @return void
   */
  void _addRideToRider(rideID) async {
    var rideObj = await _firestore.collection('rides').doc(rideID).get();
    var rideRider = rideObj.get('uid');
    var riderPastRides =
        (await _firestore.collection('users').doc(rideRider).get())
            .get('pastRides');
    riderPastRides.add(rideID);
    await _firestore
        .collection('users')
        .doc(rideRider)
        .update({'pastRides': riderPastRides});
  }

  /*
   * Cancel the current ride
   * @return void
   */
  void cancelRide() async {
    if (!_isCurrentRideInitialized) return;
    if (currentRide.status != "CANCELED") {
      await _firestore.collection('rides').doc(driver.currentRideID).update({
        'lastActivity': DateTime.now(),
        'status': 'CANCELED',
      });
    }
  }

  /*
   * On ride update, update the ride status and handle the ride accordingly
   * @param updatedRide The updated ride
   */
  void _onRideUpdate(Ride updatedRide) {
    try {
      if (currentRide.status == updatedRide.status) return;
    } catch (e) {
      logger.error(
          "Error updating ride status:  Current ride is not initialized.");
    }
    currentRide = updatedRide;
    _isCurrentRideInitialized = true;
    switch (updatedRide.status) {
      case 'CANCELED':
        cancelRide();
        startDriving();
        Payment.cancelPaymentIntentFromFirebaseByUserIdAndRideId(
            updatedRide.uid, driver.currentRideID);
        break;
      case 'IN_PROGRESS':
        // Payment intent is created on the rider side
        break;
      case 'ENDED':
        completeRide();
        startDriving();
        // Capture payment from stripe_customer payment that contains the rideID
        Payment.capturePaymentIntentFromFirebaseByUserIdAndRideId(
            updatedRide.uid, driver.currentRideID);
        break;
      default:
    }
  }

  Stream<Driver> getDriverStream() {
    return driverReference
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      return Driver.fromDocument(snapshot);
    });
  }

  Stream<CurrentShift> getCurrentShift() {
    return shiftReference
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      return CurrentShift.fromDocument(snapshot);
    });
  }

  // TODO: Audit
  Stream<List<Driver>> getNearbyDriversStream() {
    nearbyDriversListStream = geo
        .collection(collectionRef: driversCollection)
        .within(center: myLocation, radius: 50, field: 'geoFirePoint')
        .map((snapshots) =>
            snapshots.map((e) => Driver.fromDocument(e)).take(10).toList());
    return nearbyDriversListStream;
  }

  Future<List<Driver>> getNearbyDriversListWithModel(
      double radius, String cartModel) async {
    GeoFirePoint centerPoint = locationService.getCurrentGeoFirePoint();

    logger.info('SEARCH: Searching for drivers');
    logger
        .info('  - Center: ${centerPoint.latitude}, ${centerPoint.longitude}');
    logger.info('  - Radius: $radius miles');
    logger.info('  - Model: $cartModel');

    Query collectionReference = _firestore
        .collection('drivers')
        .where('isAvailable', isEqualTo: true)
        .where('cartModel', isEqualTo: cartModel);

    QuerySnapshot testQuery = await collectionReference.get();
    logger.info(
        'SEARCH: Found ${testQuery.docs.length} drivers matching filters (before geo)');

    for (var doc in testQuery.docs) {
      var data = doc.data() as Map<String, dynamic>;
      logger.info('  - Driver: ${data['firstName']} ${data['lastName']}');
      logger.info(
          '    isAvailable: ${data['isAvailable']}, cartModel: ${data['cartModel']}');
      if (data['geoFirePoint'] != null) {
        var geo = data['geoFirePoint'] as Map<String, dynamic>;
        var geopoint = geo['geopoint'] as GeoPoint;
        logger
            .info('    Location: ${geopoint.latitude}, ${geopoint.longitude}');
      }
    }

    Stream<List<Driver>> stream = geo
        .collection(collectionRef: collectionReference)
        .within(
            center: centerPoint,
            radius: radius,
            field: 'geoFirePoint',
            strictMode: false)
        .map((event) =>
            event.map((e) => Driver.fromDocument(e)).take(10).toList());

    List<Driver> nearbyDrivers = await stream.first;
    logger.info(
        'SEARCH: After geo filter: ${nearbyDrivers.length} drivers within radius');

    return nearbyDrivers;
  }

  Future<void> _updateDriverRecord() async {
    DocumentSnapshot myDriverRef = await driverReference.get();

    logger.info('DRIVER: Updating driver record for ${userService.userID}');
    logger.info('DRIVER: Document exists: ${myDriverRef.exists}');

    if (!myDriverRef.exists) {
      logger.info('DRIVER: Creating new driver document');
      await driversCollection.doc(userService.userID).set({
        'uid': userService.userID,
        'firstName': userService.user.firstName,
        'lastName': userService.user.lastName,
        'cartModel': "X",
        'profilePictureURL': userService.user.profilePictureURL,
        'geoFirePoint': locationService.getCurrentGeoFirePoint().data,
        'lastActivity': DateTime.now(),
        'isAvailable': false,
        'isWorking': false,
        'isOnBreak': false,
        'currentRideID': '',
        'fcmToken': '',
        'daysOfWeek': [],
      }, SetOptions(merge: true));
      logger.info('DRIVER: Driver document created');
    } else {
      // Just update location, don't change working status
      logger.info('DRIVER: Updating existing driver location');
      await driversCollection.doc(userService.userID).update({
        'geoFirePoint': locationService.getCurrentGeoFirePoint().data,
        'lastActivity': DateTime.now(),
      });
    }

    // Verify current state
    DocumentSnapshot verifyDoc = await driverReference.get();
    Map<String, dynamic> data = verifyDoc.data() as Map<String, dynamic>;
    logger.info('DRIVER: Current states:');
    logger.info('  - isAvailable: ${data['isAvailable']}');
    logger.info('  - isWorking: ${data['isWorking']}');
    logger.info('  - cartModel: ${data['cartModel']}');
  }

  /*
   * Clock in the driver
   * @return Future<Map<String, dynamic>> The result of the clock in operation
   */
  Future<Map<String, dynamic>> clockIn() async {
    try {
      logger.info('DRIVER: clockIn start');

      final DocumentSnapshot driverDoc = await driverReference.get();

      if (!driverDoc.exists || driverDoc.data() == null) {
        logger.error('DRIVER: clockIn failed - driver document not found');
        return {
          'success': false,
          'response': 'Driver profile not found.',
        };
      }

      final data = driverDoc.data() as Map<String, dynamic>;

      final String driveruid =
          (data['uid'] ?? auth.FirebaseAuth.instance.currentUser?.uid ?? '')
              .toString();

      final dynamic rawDays = data['daysOfWeek'];

      List<int> daysOfWeek = [];

      if (rawDays is List) {
        daysOfWeek = rawDays
            .map((e) => int.tryParse(e.toString()))
            .where((e) => e != null)
            .cast<int>()
            .toList();
      } else if (rawDays is String) {
        daysOfWeek = rawDays
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .where((e) => e != null)
            .cast<int>()
            .toList();
      }

      logger.info(
        'DRIVER: clockIn using uid=$driveruid | daysOfWeek=$daysOfWeek | shiftuid=$shiftuid',
      );
      logger.info('DRIVER: today weekday check = ${DateTime.now().weekday}');

      if (driveruid.isEmpty) {
        return {
          'success': false,
          'response': 'Driver uid is missing.',
        };
      }

      HttpsCallableResult result = await driverClockInFunction.call(
        <String, dynamic>{
          'daysOfWeek': daysOfWeek,
          'driveruid': driveruid,
          'shiftuid': shiftuid,
        },
      );

      logger.info('DRIVER: clockIn raw result = ${result.data}');

      final String response =
          (result.data['response'] ?? 'No response').toString();
      final bool success = result.data['success'] == true;

      return {'success': success, 'response': response};
    } catch (e) {
      logger.error('DRIVER: clockIn exception: $e');
      return {
        'success': false,
        'response': 'Clock in exception: $e',
      };
    }
  }

  /*
   * Clock out the driver
   * @return Future<Map<String, dynamic>> The result of the clock out operation
   */
  Future<Map<String, dynamic>> clockOut() async {
    try {
      logger.info('DRIVER: clockOut start');

      final DocumentSnapshot driverDoc = await driverReference.get();

      if (!driverDoc.exists || driverDoc.data() == null) {
        logger.error('DRIVER: clockOut failed - driver document not found');
        return {
          'success': false,
          'response': 'Driver profile not found.',
        };
      }

      final data = driverDoc.data() as Map<String, dynamic>;

      final String driveruid =
          (data['uid'] ?? auth.FirebaseAuth.instance.currentUser?.uid ?? '')
              .toString();

      logger.info('DRIVER: clockOut using uid=$driveruid');

      if (driveruid.isEmpty) {
        return {
          'success': false,
          'response': 'Driver uid is missing.',
        };
      }

      HttpsCallableResult result = await driverClockOutFunction.call(
        <String, dynamic>{
          'driveruid': driveruid,
          'shiftuid': shiftuid,
        },
      );

      logger.info('DRIVER: clockOut raw result = ${result.data}');

      final String response =
          (result.data['response'] ?? 'No response').toString();
      final bool success = result.data['success'] == true;

      return {'success': success, 'response': response};
    } catch (e) {
      logger.error('DRIVER: clockOut exception: $e');
      return {
        'success': false,
        'response': 'Clock out exception: $e',
      };
    }
  }

  /*
   * Start the driver's break
   * @return Future<Map<String, dynamic>> The result of the start break operation
   */
  Future<Map<String, dynamic>> startBreak() async {
    try {
      logger.info('DRIVER: startBreak start');

      final DocumentSnapshot driverDoc = await driverReference.get();

      if (!driverDoc.exists || driverDoc.data() == null) {
        logger.error('DRIVER: startBreak failed - driver document not found');
        return {
          'success': false,
          'response': 'Driver profile not found.',
        };
      }

      final data = driverDoc.data() as Map<String, dynamic>;

      final String driveruid =
          (data['uid'] ?? auth.FirebaseAuth.instance.currentUser?.uid ?? '')
              .toString();

      logger.info('DRIVER: startBreak using uid=$driveruid shiftuid=$shiftuid');

      if (driveruid.isEmpty) {
        return {
          'success': false,
          'response': 'Driver uid is missing.',
        };
      }

      HttpsCallableResult result = await driverStartBreakFunction.call(
        <String, dynamic>{
          'driveruid': driveruid,
          'shiftuid': shiftuid,
        },
      );

      logger.info('DRIVER: startBreak raw result = ${result.data}');

      final String response =
          (result.data['response'] ?? 'No response').toString();
      final bool success = result.data['success'] == true;

      return {'success': success, 'response': response};
    } catch (e) {
      logger.error('DRIVER: startBreak exception: $e');
      return {
        'success': false,
        'response': 'Start break exception: $e',
      };
    }
  }

  /*
   * End the driver's break
   * @return Future<Map<String, dynamic>> The result of the end break operation
   */
  Future<Map<String, dynamic>> endBreak() async {
    HttpsCallableResult result = await driverEndBreakFunction
        .call(<String, dynamic>{'driveruid': driver.uid, 'shiftuid': shiftuid});
    String response = (result.data['response']).toString();
    bool success = result.data['success'];

    return {'success': success, 'response': response};
  }
}
