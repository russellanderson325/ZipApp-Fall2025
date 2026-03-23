import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place_plus/google_place_plus.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:zipapp/business/drivers.dart';
import 'package:zipapp/business/ride.dart';
import 'package:zipapp/business/user.dart';
import 'package:zipapp/constants/keys.dart';
import 'package:zipapp/constants/zip_colors.dart';
import 'package:zipapp/constants/zip_design.dart';
import 'package:zipapp/models/user.dart';
import 'package:zipapp/services/position_service.dart';
import 'package:zipapp/ui/screens/rider_only/search_screen.dart';
import 'package:zipapp/ui/screens/rider_only/vehicle_ride_status_confirmation_screen.dart';
import 'package:zipapp/ui/screens/rider_only/vehicles_screen.dart';
import 'package:zipapp/ui/widgets/message_overlay.dart';
import 'package:zipapp/logger.dart';
import 'package:geolocator/geolocator.dart';

class MapWidget extends StatefulWidget {
  final bool driver;
  const MapWidget({super.key, required this.driver});

  @override
  State<MapWidget> createState() => MapWidgetSampleState();
}

class MapWidgetSampleState extends State<MapWidget> {
  final AppLogger logger = AppLogger();
  //general map code
  String mapTheme = '';
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();
  PositionService positionService = PositionService();
  LatLng? userLatLng, searchLatLng;
  final markers = <Marker>[];
  final polylines = <Polyline>[];
  PolylinePoints polylinePoints = PolylinePoints(apiKey: Keys.map);
  DriverService driverService = DriverService();
  Map<String, bool> driverStates = {
    'isWorking': false,
    'onBreak': false,
    'isLoadingDriverStatus': true,
  };
  DateTime lastClockInButtonPress = DateTime(0);
  DateTime lastClockOutButtonPress = DateTime(0);
  DateTime lastStartBreakButtonPress = DateTime(0);
  DateTime lastEndBreakButtonPress = DateTime(0);
  UserService userService = UserService();
  RideService rideService = RideService();
  bool isRiding = false;
  int iterateKey = 0;

  @override
  void initState() {
    super.initState();

    // Initialize with Auburn coordinates immediately to ensure map loads
    userLatLng = const LatLng(32.6099, -85.4808);
    logger.info('Initial position set to Auburn: $userLatLng');

    DefaultAssetBundle.of(context)
        .loadString('assets/mapthemes/uber_theme.json')
        .then((value) {
      mapTheme = value;
    });

    // Listen to user.isRiding changes
    userService.userStream.listen(updateUI);

    // Start location fetching immediately
    _getCurrentLocationAndCenter();
  }

  void _getCurrentLocationAndCenter() async {
    try {
      // Check location permissions first
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.info('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        logger.info('Location permissions are permanently denied');
        return;
      }

      // Get last known position first (faster)
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          userLatLng = LatLng(lastKnown.latitude, lastKnown.longitude);
          logger.info('Using last known position: $userLatLng');
        });
        _centerMapOnUser();
      }

      // Then get current position for accuracy
      Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          userLatLng =
              LatLng(currentPosition.latitude, currentPosition.longitude);
          logger.info('Updated to current position: $userLatLng');
        });
        _centerMapOnUser();
      }

      // Update the driver status after getting location
      updateDriverStatus().then((value) async {
        if (userService.user.isRiding) {
          Map<String, dynamic>? destinationAddress = await rideService
              .fetchRideDestination(userService.user.currentRideId);
          GeoPoint destinationGeoPoint = destinationAddress?['geopoint'];

          double lat = destinationGeoPoint.latitude;
          double lng = destinationGeoPoint.longitude;
          addSearchedMarkerByCoordinate(lat, lng);
        }
      });
    } catch (error) {
      logger.error('ERROR getting position: $error');
      // Keep Auburn coordinates as fallback - map is already loaded
    }
  }

  void _centerMapOnUser() async {
    if (!mounted || userLatLng == null) return;

    // Wait for map controller to be ready
    if (_controller.isCompleted) {
      try {
        final GoogleMapController controller = await _controller.future;
        await controller.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: userLatLng!, zoom: 17.5),
        ));
        logger.info('Camera centered on user location: $userLatLng');
      } catch (e) {
        logger.error('Error centering map: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key(iterateKey.toString()),
      mainAxisSize: MainAxisSize.min,
      children: [
        buildTopBar(),
        Expanded(
          child: buildMap(),
        ),
      ],
    );
  }

  Widget buildTopBar() {
    if (widget.driver) {
      if (driverStates['isLoadingDriverStatus'] ?? false) {
        return const SizedBox(
          height: 68,
          child: Center(
            child: CircularProgressIndicator(
              color: Colors.black,
            ),
          ),
        );
      } else {
        return driverBox(MediaQuery.of(context).size.width, 68);
      }
    } else {
      return userService.isRiding()
          ? currentRide(MediaQuery.of(context).size.width, 68)
          : searchBox(MediaQuery.of(context).size.width, 68);
    }
  }

// Build the Google Map widget
  Widget buildMap() {
    return userLatLng == null
        ? const Center(
            child: CircularProgressIndicator(
            color: Colors.black,
          ))
        : GoogleMap(
            myLocationEnabled: true,
            compassEnabled: true,
            initialCameraPosition:
                CameraPosition(target: userLatLng!, zoom: 17.5),
            mapToolbarEnabled: false,
            markers: markers.toSet(),
            myLocationButtonEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
                controller.setMapStyle(mapTheme);
                // Center on user location as soon as map is created
                _centerMapOnUser();
              }
            },
            polylines: polylines.toSet(),
            zoomControlsEnabled: false,
          );
  }

  //driver code
  void clockIn() async {
    if (DateTime.now().difference(lastClockInButtonPress).inSeconds < 5) {
      if (mounted) {
        MessageOverlay.angryMessage(
            context, "Please wait a few seconds before trying again.");
      }
      return;
    }

    lastClockInButtonPress = DateTime.now();

    if (mounted) {
      setState(() {
        driverStates['isLoadingDriverStatus'] = true;
      });
    }

    try {
      logger.info('MAP: Clock in pressed');

      Map<String, dynamic> response = await driverService.clockIn();

      logger.info('MAP: clockIn response = $response');

      if (!response['success']) {
        if (mounted) {
          setState(() {
            driverStates['isLoadingDriverStatus'] = false;
          });
          MessageOverlay.angryMessage(
            context,
            response['response']?.toString() ?? 'Clock in failed.',
          );
        }
        return;
      }

      driverService.startDriving();

      if (mounted) {
        setState(() {
          driverStates['isOnBreak'] = false;
          driverStates['isWorking'] = true;
          driverStates['isLoadingDriverStatus'] = false;
        });
      }
    } catch (e) {
      logger.error('MAP: clockIn exception: $e');

      if (mounted) {
        setState(() {
          driverStates['isLoadingDriverStatus'] = false;
        });
        MessageOverlay.angryMessage(
          context,
          'Clock in failed: $e',
        );
      }
    }
  }

  void clockOut() async {
    if (mounted) {
      setState(() {
        driverStates['isLoadingDriverStatus'] = true;
      });
    }

    try {
      logger.info('MAP: Clock out pressed');

      Map<String, dynamic> response = await driverService.clockOut();

      logger.info('MAP: clockOut response = $response');

      if (!response['success']) {
        if (mounted) {
          setState(() {
            driverStates['isLoadingDriverStatus'] = false;
          });

          MessageOverlay.angryMessage(
            context,
            response['response']?.toString() ?? 'Clock out failed.',
          );
        }
        return;
      }

      driverService.stopDriving();

      if (mounted) {
        setState(() {
          driverStates['isWorking'] = false;
          driverStates['isOnBreak'] = false;
          driverStates['isLoadingDriverStatus'] = false;
        });
      }
    } catch (e) {
      logger.error('MAP: clockOut exception: $e');

      if (mounted) {
        setState(() {
          driverStates['isLoadingDriverStatus'] = false;
        });

        MessageOverlay.angryMessage(
          context,
          'Clock out failed: $e',
        );
      }
    }
  }

  void startBreak() async {
    if (mounted) {
      setState(() {
        driverStates['isLoadingDriverStatus'] = true;
      });
    }

    try {
      logger.info('MAP: Start break pressed');

      Map<String, dynamic> response = await driverService.startBreak();

      logger.info('MAP: startBreak response = $response');

      if (!response['success']) {
        if (mounted) {
          setState(() {
            driverStates['isLoadingDriverStatus'] = false;
          });

          MessageOverlay.angryMessage(
            context,
            response['response']?.toString() ?? 'Start break failed.',
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          driverStates['isOnBreak'] = true;
          driverStates['isWorking'] = false;
          driverStates['isLoadingDriverStatus'] = false;
        });
      }
    } catch (e) {
      logger.error('MAP: startBreak exception: $e');

      if (mounted) {
        setState(() {
          driverStates['isLoadingDriverStatus'] = false;
        });

        MessageOverlay.angryMessage(
          context,
          'Start break failed: $e',
        );
      }
    }
  }

  void endBreak() async {
    if (DateTime.now().difference(lastEndBreakButtonPress).inSeconds < 5) {
      if (mounted) {
        MessageOverlay.angryMessage(
            context, "Please wait a few seconds before trying again.");
      }
      return;
    }
    lastEndBreakButtonPress = DateTime.now();

    if (mounted) {
      setState(() {
        driverStates['isLoadingDriverStatus'] = true;
      });
    }

    var response = await driverService.endBreak();
    if (!response['success']) {
      if (mounted) MessageOverlay.angryMessage(context, response['response']);
      return;
    }

    driverService.startDriving();
    if (mounted) {
      setState(() {
        driverStates['isOnBreak'] = false;
        driverStates['isWorking'] = true;
        driverStates['isLoadingDriverStatus'] = false;
      });
    }
  }

  Future<void> updateDriverStatus() async {
    // Fetch the driver states asynchronously.
    Map<String, bool> states = await driverService.getDriverStates();
    // Once the data is available, then update the state synchronously.
    setState(() {
      driverStates = {
        'isWorking': states['isWorking']!,
        'isOnBreak': states['isOnBreak']!,
        'isLoadingDriverStatus': false,
      };
    });
  }

  Future<void> updateUI(User user) async {
    if (mounted) {
      setState(() {
        iterateKey++;
      });
    }
  }

  SizedBox currentRide(double screenWidth, double screenHeight) {
    return SizedBox(
      width: screenWidth,
      height: 68,
      child: Container(
        decoration: const BoxDecoration(
          color: ZipColors.primaryBackground,
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: TextButton(
          onPressed: () {
            // Bring up the vehicle ride status confirmation screen
            VehicleRideStatusConfirmationScreenState
                .showVehicleRequestAwaitingConfirmationScreen(
                    context, rideService, _resetMarkers);
          },
          style: ZipDesign.yellowButtonStyle,
          child: const Text('View Active Ride'),
        ),
      ),
    );
  }

  SizedBox driverBox(double screenWidth, double screenHeight) {
    return SizedBox(
      width: screenWidth,
      height: 68,
      child: Container(
        // decoration: const BoxDecoration(
        //   color: ZipColors.primaryBackground,
        // ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: driverStates['isWorking']!
            ? Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed:
                          driverStates['isOnBreak']! ? endBreak : startBreak,
                      icon: driverStates['isOnBreak']!
                          ? const Icon(LucideIcons.play)
                          : const Icon(LucideIcons.pause),
                      label: driverStates['isOnBreak']!
                          ? const Text('Resume driving')
                          : const Text('Start break'),
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                        padding:
                            WidgetStateProperty.all(const EdgeInsets.all(0)),
                        iconColor: WidgetStateProperty.all(Colors.black),
                        iconSize: WidgetStateProperty.all(16),
                        foregroundColor: WidgetStateProperty.all(Colors.black),
                        backgroundColor:
                            WidgetStateProperty.all(ZipColors.zipYellow),
                        textStyle: WidgetStateProperty.all(ZipDesign.labelText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: clockOut,
                      icon: const Icon(LucideIcons.logOut),
                      label: const Text('Clock out'),
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                        padding:
                            WidgetStateProperty.all(const EdgeInsets.all(0)),
                        iconColor: WidgetStateProperty.all(Colors.black),
                        iconSize: WidgetStateProperty.all(16),
                        foregroundColor: WidgetStateProperty.all(Colors.black),
                        backgroundColor:
                            WidgetStateProperty.all(ZipColors.zipYellow),
                        textStyle: WidgetStateProperty.all(ZipDesign.labelText),
                      ),
                    ),
                  ),
                ],
              )
            : TextButton.icon(
                onPressed: clockIn,
                icon: const Icon(LucideIcons.logIn),
                label: const Text('Clock in as a driver'),
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
                  padding: WidgetStateProperty.all(const EdgeInsets.all(0)),
                  iconColor: WidgetStateProperty.all(Colors.black),
                  iconSize: WidgetStateProperty.all(16),
                  foregroundColor: WidgetStateProperty.all(Colors.black),
                  backgroundColor: WidgetStateProperty.all(ZipColors.zipYellow),
                  textStyle: WidgetStateProperty.all(ZipDesign.labelText),
                ),
              ),
      ),
    );
  }

  //rider code

  SizedBox searchBox(double screenWidth, double screenHeight) {
    return SizedBox(
      width: screenWidth,
      height: 68,
      child: Container(
        decoration: const BoxDecoration(
          color: ZipColors.primaryBackground,
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: GestureDetector(
          onTap: () => openSearchScreen(),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: ZipColors.boxBorder, width: 1.0),
              color: Colors.white,
            ),
            child: const Row(
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 15.0),
                  child: Icon(Icons.search, color: Colors.black, size: 30.0),
                ),
                Padding(
                  padding: EdgeInsets.only(left: 15.0),
                  child: Text(
                    'Where would you like to go?',
                    style: TextStyle(
                      color: Colors.black,
                      decoration: TextDecoration.none,
                      fontSize: 16.0,
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void openSearchScreen() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (context) => const SearchScreen()));
    if (result != null) {
      addSearchedMarker(result);
    }
  }

  void addSearchedMarker(LocalSearchResult searchResult) async {
    GooglePlace googlePlace = GooglePlace(Keys.map);
    await googlePlace.details.get(searchResult.placeId).then(
      (value) async {
        if (value != null &&
            value.result != null &&
            value.result!.geometry != null &&
            value.result!.geometry!.location != null) {
          // Get the destination coordinates
          double destLat = value.result!.geometry!.location!.lat!;
          double destLng = value.result!.geometry!.location!.lng!;
          LatLng destination = LatLng(destLat, destLng);

          // Check if destination is within driver radius
          if (userLatLng != null &&
              !isWithinDriverRadius(destination, radiusMiles: 3.0)) {
            // Show error dialog for location too far away
            if (mounted) {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFFFEFCE8),
                    title: const Text('Location Too Far'),
                    content: const Text(
                        'Sorry, the selected destination is outside our service area. Please choose a location within 3 miles of Jordan-Hare Stadium.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'OK',
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                    ],
                  );
                },
              );
            }
            return; // Exit early, don't add the marker
          }

          if (mounted) {
            setState(() {
              searchLatLng = LatLng(value.result!.geometry!.location!.lat!,
                  value.result!.geometry!.location!.lng!);
            });
            PolylineResult result = await _addSearchResult(searchResult);
            _moveCamera(
                latlng: LatLng(value.result!.geometry!.location!.lat! - 0.0015,
                    value.result!.geometry!.location!.lng!));
            if (result.totalDistanceValue != null) {
              // Show the vehicle request screen only if the distance value is not null
              VehiclesScreenState.showVehiclesScreen(
                context,
                result.totalDistanceValue!.toDouble(),
                value.result!.geometry!.location!.lat!,
                value.result!.geometry!.location!.lng!,
                _resetMarkers,
              );
            } else {
              // Handle the case where distanceValue is null, perhaps notify the user or log an error
              logger.error(
                  "Error: PolylineResult returned null for distanceValue.");
            }
          }
        } else {
          // Handle the case where GooglePlace details return null
          logger.error("Error: Failed to retrieve place details.");
        }
      },
    ).catchError((error) {
      // Handle potential errors like network issues
      logger.error("Error fetching place details: $error");
    });
  }

  void addSearchedMarkerByCoordinate(double latitude, double longitude) async {
    setState(() {
      searchLatLng = LatLng(latitude, longitude);
    });

    if (mounted) {
      // Assuming you have a function to create and add a marker based on latitude and longitude
      await _addLatLngAsSearchResult(latitude, longitude);
      _moveCamera(latlng: LatLng(latitude - 0.0015, longitude));
    }
  }

  Future<PolylineResult> _addLatLngAsSearchResult(
      double latitude, double longitude) async {
    searchLatLng = LatLng(latitude, longitude);
    LocalSearchResult searchResult =
        LocalSearchResult(name: "Custom Location", placeId: "custom");
    return await _addSearchResult(searchResult);
  }

  Future<PolylineResult> _addSearchResult(
      LocalSearchResult searchResult) async {
    _resetMarkers();
    markers.add(Marker(
      markerId: const MarkerId("userPosition"),
      position: userLatLng!,
      infoWindow: const InfoWindow(title: "You are here"),
    ));
    BitmapDescriptor customIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(24, 24)),
      'assets/destination_map_marker.png',
    );
    setState(() {
      markers.add(Marker(
        markerId: MarkerId(searchResult.placeId),
        position: searchLatLng!,
        infoWindow: InfoWindow(title: searchResult.name),
        icon: customIcon,
      ));
    });
    return await _updatePolylines();
  }

  void _moveCamera({LatLng? latlng, double zoom = 17.0}) async {
    latlng ??= userLatLng!;
    final GoogleMapController controller = await _controller.future;
    await controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: latlng, zoom: zoom)));
  }

  void _resetMarkers() {
    if (mounted) {
      setState(() {
        markers.clear();
      });
    }
    _updatePolylines();
  }

  Future<PolylineResult> _updatePolylines() async {
    if (markers.length > 1) {
      PolylineRequest polylineRequest = PolylineRequest(
        origin: PointLatLng(
            markers.first.position.latitude, markers.first.position.longitude),
        destination: PointLatLng(
            markers.last.position.latitude, markers.last.position.longitude),
        mode: TravelMode.driving,
      );

      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        request: polylineRequest,
        // googleApiKey: Keys.map,
      );

      if (result.points.isNotEmpty) {
        List<LatLng> polylineCoordinates = [];
        result.points.map((PointLatLng point) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        });
        Polyline polyline = Polyline(
          polylineId: const PolylineId("userRoute"),
          color: const Color.fromARGB(255, 255, 193, 21),
          points: polylineCoordinates,
          width: 5,
          visible: true,
        );
        if (mounted) {
          setState(() {
            polylines.add(polyline);
          });
        }
      }
      return result;
    } else {
      if (mounted) {
        setState(
          () {
            polylines.clear();
          },
        );
      }
      return PolylineResult();
    }
  }
}

bool isWithinDriverRadius(LatLng? destination, {double radiusMiles = 3.0}) {
  // Geofence center: Jordan-Hare Stadium
  const double geofenceLat = 32.6025;
  const double geofenceLng = -85.4890;

  if (destination == null) return false;

  const double milesToMeters = 1609.34;
  double distanceMeters = Geolocator.distanceBetween(
    geofenceLat,
    geofenceLng,
    destination.latitude,
    destination.longitude,
  );

  return distanceMeters <= (radiusMiles * milesToMeters);
}
