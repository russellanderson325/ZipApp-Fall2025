import 'package:flutter/material.dart';
import 'package:zipapp/business/user.dart';
import 'package:zipapp/business/drivers.dart';
import 'package:zipapp/models/request.dart';
import 'package:zipapp/ui/widgets/driver_request_popup.dart';
import 'package:zipapp/ui/widgets/map.dart' as mapwidget;
import 'package:zipapp/logger.dart';


class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  UserService userService = UserService();
  final DriverService _driverService = DriverService();
  final AppLogger logger = AppLogger();

  @override
  void initState() {
    super.initState();
    _setupRequestCallbacks();
  }

  void _setupRequestCallbacks() {
    _driverService.setRequestCallbacks(
      onRequest: _handleNewRequest,
      onTimeout: _handleRequestTimeout,
    );
  }

  void _handleNewRequest(Request request) {
    if (!mounted) return;
    logger.info('UI: New request received - showing popup');
    showRideRequestPopup(context, request, () {});
  }

  void _handleRequestTimeout(String requestId) {
    if (!mounted) return;
    logger.info('UI: Request $requestId timed out');
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
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
}