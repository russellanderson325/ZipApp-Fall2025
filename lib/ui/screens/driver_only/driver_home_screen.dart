import 'package:flutter/material.dart';
import 'package:zipapp/business/user.dart';
import 'package:zipapp/business/drivers.dart';
import 'package:zipapp/models/request.dart';
import 'package:zipapp/ui/widgets/driverRequestPopUp.dart';
import 'package:zipapp/ui/widgets/map.dart' as mapwidget;

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  UserService userService = UserService();
  final DriverService _driverService = DriverService();

  @override
  void initState() {
    super.initState();
    // Setup callbacks to handle incoming ride requests
    _setupRequestCallbacks();
  }

  /// Setup callbacks to listen for incoming ride requests
  void _setupRequestCallbacks() {
    _driverService.setRequestCallbacks(
      onRequest: _handleNewRequest,
      onTimeout: _handleRequestTimeout,
    );
  }

  /// Called when a new ride request is received
  void _handleNewRequest(Request request) {
    if (!mounted) return;
    
    print('UI: New request received - showing popup');
    
    // Show the popup dialog
    showRideRequestPopup(
      context,
      request,
      () {
        // This callback is called when the dialog is dismissed
        print('UI: Request popup dismissed');
      },
    );
  }

  /// Called when a request times out
  void _handleRequestTimeout(String requestId) {
    if (!mounted) return;
    
    print('UI: Request $requestId timed out');
    
    // Close any open dialogs
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    
    // Show a snackbar notification
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ride request timed out'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        titleSpacing: 0.0,
        leading: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 0),
            child: Image.asset(
              'assets/two_tone_zip_black.png',
              width: 40,
              height: 40,
            )),
        title: Text('Good afternoon, ${userService.user.firstName}',
            style: const TextStyle(
                fontSize: 24.0,
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w500)),
      ),
      body: const Center(
        child: mapwidget.MapWidget(driver: true),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
