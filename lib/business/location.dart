import 'dart:async';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
//import 'package:location_permissions/location_permissions.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  GeoFlutterFire geo = GeoFlutterFire();
  Position? position;
  bool initialized = false;
  LocationSettings locationOptions = const LocationSettings(
      accuracy: LocationAccuracy.high, 
      distanceFilter: 25, 
      timeLimit: Duration(seconds: 10));
  Stream<Position> positionStream = const Stream.empty();
  StreamSubscription<Position>? positionSub;
  bool isPositionSubInitialized = false;
  
  // Tracks when initial position is ready
  Completer<void>? _initCompleter;

  factory LocationService() {
    return _instance;
  }

  LocationService._internal() {
    if (kDebugMode) {
      print("LocationService created");
    }
  }

  Future<bool> setupService({bool reinit = false}) async {
    try {
      if (kDebugMode) {
        print("LocationService: Starting setup...");
      }

      // Cancel existing subscription if any
      if (isPositionSubInitialized && positionSub != null) {
        await positionSub!.cancel();
        isPositionSubInitialized = false;
      }

      // Create new completer for this initialization
      _initCompleter = Completer<void>();

      // Check and request permissions
      PermissionStatus status =
          await Permission.location.status;

      if (kDebugMode) {
        print("LocationService: Current permission status: $status");
      }

      // Get permission from user
      while (status != PermissionStatus.granted) {
        if (kDebugMode) {
          print("LocationService: Requesting permissions...");
        }
        status = await Permission.location.status;
        
        if (status == PermissionStatus.denied || 
            status == PermissionStatus.restricted) {
          if (kDebugMode) {
            print("LocationService: Permission denied by user");
          }
          _initCompleter?.completeError(
            Exception('Location permission denied')
          );
          return false;
        }
      }

      if (kDebugMode) {
        print("LocationService: Permissions granted, getting current position...");
      }

      // Get initial position with timeout and fallback
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        if (kDebugMode) {
          print("LocationService: ✓ Got current position: ${position!.latitude}, ${position!.longitude}");
        }
      } on TimeoutException {
        if (kDebugMode) {
          print("LocationService: Timeout getting position, trying last known...");
        }
        
        // Fallback to last known position
        position = await Geolocator.getLastKnownPosition();
        
        if (position == null) {
          if (kDebugMode) {
            print("LocationService: No position available");
          }
          _initCompleter?.completeError(
            Exception('Unable to get location: timeout')
          );
          return false;
        }
        
        if (kDebugMode) {
          print("LocationService: ✓ Using last known position: ${position!.latitude}, ${position!.longitude}");
        }
      } catch (e) {
        if (kDebugMode) {
          print("LocationService: Error getting position: $e");
        }
        _initCompleter?.completeError(e);
        return false;
      }

      // Creating the position stream with location options and debouncing
      if (kDebugMode) {
        print("LocationService: Setting up position stream...");
      }

      positionStream = Geolocator.getPositionStream(
        locationSettings: locationOptions
      )
          .transform(debouncePositionStream(const Duration(seconds: 10)))
          .asBroadcastStream();
      
      positionSub = positionStream.listen(
        (Position newPosition) {
          position = newPosition;
          if (kDebugMode) {
            print("LocationService: Position updated: ${newPosition.latitude}, ${newPosition.longitude}");
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print("LocationService: Position stream error: $error");
          }
        },
      );

      isPositionSubInitialized = true;
      initialized = true;
      _initCompleter?.complete();

      if (kDebugMode) {
        print("LocationService: ✓ Setup complete");
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print("LocationService: Error initializing LocationService: $e");
      }
      _initCompleter?.completeError(e);
      initialized = false;
      return false;
    }
  }

  // Ensure service is ready before getting position
  Future<void> ensureInitialized() async {
    if (initialized && position != null) {
      return; // Already initialized
    }

    if (_initCompleter != null) {
      // Initialization in progress, wait for it
      await _initCompleter!.future;
      return;
    }

    // Not initialized, do it now
    bool success = await setupService();
    if (!success) {
      throw Exception('Failed to initialize LocationService');
    }
  }

  // Async version that waits for initialization
  Future<GeoFirePoint> getCurrentGeoFirePointAsync() async {
    await ensureInitialized();
    
    if (position == null) {
      throw Exception('Position is null after initialization');
    }

    return geo.point(
      latitude: position!.latitude, 
      longitude: position!.longitude
    );
  }

  // Synchronous version with better error handling
  GeoFirePoint getCurrentGeoFirePoint() {
    if (!initialized) {
      throw Exception(
        'LocationService not initialized. Call setupService() or use getCurrentGeoFirePointAsync() instead.'
      );
    }

    if (position == null) {
      throw Exception(
        'Position not available. LocationService may still be acquiring location.'
      );
    }

    return geo.point(
      latitude: position!.latitude, 
      longitude: position!.longitude
    );
  }

  // Get current position with refresh
  Future<Position> getCurrentPosition({bool forceRefresh = false}) async {
    await ensureInitialized();

    if (forceRefresh || position == null) {
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } on TimeoutException {
        if (kDebugMode) {
          print("LocationService: Timeout refreshing position");
        }
        // Use cached position if available
        position ??= await Geolocator.getLastKnownPosition();
      }
    }

    if (position == null) {
      throw Exception('Unable to get position');
    }

    return position!;
  }

  // Check if location is available
  Future<bool> isLocationAvailable() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) {
          print('LocationService: Location services are disabled');
        }
        return false;
      }

      PermissionStatus permission = 
          await Permission.location.status;
      
      if (kDebugMode) {
        print('LocationService: Permission status: $permission');
      }
      
      return permission == PermissionStatus.granted;
    } catch (e) {
      if (kDebugMode) {
        print('LocationService: Error checking availability: $e');
      }
      return false;
    }
  }

  // Get debug status
  Map<String, dynamic> getStatus() {
    return {
      'initialized': initialized,
      'hasPosition': position != null,
      'latitude': position?.latitude ?? 'null',
      'longitude': position?.longitude ?? 'null',
      'accuracy': position?.accuracy ?? 'null',
      'timestamp': position?.timestamp.toString() ?? 'null',
    };
  }

  /// Clean up resources
  Future<void> dispose() async {
    if (isPositionSubInitialized && positionSub != null) {
      await positionSub!.cancel();
      isPositionSubInitialized = false;
    }
    initialized = false;
    position = null;
  }
}

// Debounce the position stream to avoid spamming the database with updates
StreamTransformer<Position, Position> debouncePositionStream(Duration interval) {
  DateTime? lastTime;

  return StreamTransformer.fromHandlers(
    handleData: (Position data, EventSink<Position> sink) {
      final now = DateTime.now();
      if (lastTime == null || now.difference(lastTime!) > interval) {
        lastTime = now;
        sink.add(data);
      }
    },
  );
}