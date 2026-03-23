import "dart:async";
import "package:flutter/material.dart";
import "package:lucide_icons/lucide_icons.dart";

import "package:zipapp/business/ride.dart";
import "package:zipapp/business/user.dart";
import "package:zipapp/constants/zip_colors.dart";
import "package:zipapp/constants/zip_design.dart";
import "package:zipapp/models/rides.dart";

class VehicleRideStatusConfirmationScreen extends StatefulWidget {
  final RideService ride;
  final Function resetMap;
  const VehicleRideStatusConfirmationScreen({
    super.key,
    required this.ride,
    required this.resetMap,
  });

  @override
  State<VehicleRideStatusConfirmationScreen> createState() =>
      VehicleRideStatusConfirmationScreenState();
}

class VehicleRideStatusConfirmationScreenState
    extends State<VehicleRideStatusConfirmationScreen> {
  VehicleRideStatusConfirmationScreenState();
  String rideId = "";
  String statusMessage = "";
  String rideStatus = "";
  int incrementKey = 0;
  RideService? ride;
  UserService userService = UserService();
  bool _isMounted = false;
  String status = "";
  StreamSubscription<Ride>? _rideSubscription;
  Ride? _latestRide;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    statusMessage = "";
    ride = widget.ride;

    _rideSubscription = ride?.getRideStream().listen((rideDoc) {
      _latestRide = rideDoc;
      statusUpdate(rideDoc.status);
    });
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    if (!userService.isRiding()) {
      Future.microtask(() => widget.resetMap());
      ride?.cancelRide();
    }
    _isMounted = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Ride Information"),
          automaticallyImplyLeading: false,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
        ),
        backgroundColor: Colors.white,
        body: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.only(left: 24, right: 24),
          child: ListView(
            children: <Widget>[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: ZipColors.boxBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Ride Status",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      statusMessage.isNotEmpty ? statusMessage : "Waiting for ride updates...",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Driver",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (_latestRide?.driverName != null && _latestRide!.driverName.isNotEmpty)
                          ? _latestRide!.driverName
                          : "Driver not assigned yet",
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Trip Progress",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status == "INITIALIZING" || status == "WAITING"
                          ? "Looking for and connecting to a driver."
                          : status == "IN_PROGRESS"
                              ? "Your driver is connected and your ride is active."
                              : status == "ENDED"
                                  ? "Ride completed successfully."
                                  : status == "CANCELED"
                                      ? "Ride was canceled."
                                      : "Ride information unavailable.",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: ZipColors.boxBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    "Map placeholder for Active Rider screen",
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    if (status != "CANCELED") {
                      ride?.cancelRide();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  style: ZipDesign.redButtonStyle,
                  child: Text(
                    (status != "CANCELED" || status == "ENDED")
                        ? 'Cancel Ride'
                        : 'Close',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              // const Center(
              //   child: Text(
              //     "If the ride is cancelled, no charge will be made",
              //     style: TextStyle(
              //       color: Colors.black,
              //       fontSize: 10,
              //     ),
              //   )
              // ),
            ],
          ),
        ));
  }

  /*
   * Update the status of the ride
   * @param status The status of the ride
   * @return void
   */
  void statusUpdate(String status) {
    this.status = status;
    if (_isMounted) {
      setState(() {
        rideStatus = status;
        incrementKey++;
        switch (status) {
          case "INITIALIZING":
            statusMessage = "Searching for a driver...";
            break;
          case "WAITING":
            statusMessage = "Waiting for driver to accept...";
            break;
          case "IN_PROGRESS":
            statusMessage = "Driver connected and en route...";
            userService.startRide(ride!.rideID);
            break;
          case "ENDED":
            statusMessage =
                "Ride has ended, thank you for riding with us. Your payment has been processed.";
            userService.endRide();
            Future.microtask(() => widget.resetMap());
            break;
          case "CANCELED":
            statusMessage = "Ride canceled. No charge has been made.";
            userService.endRide();
            Future.microtask(() => widget.resetMap());
            break;
        }
      });
    }
  }

  /*
   * Show the VehicleRequestAwaitingConfirmationScreenState as a bottom sheet
   * @param context The context
   * @return void
   */
  static void showVehicleRequestAwaitingConfirmationScreen(
    BuildContext context,
    RideService ride,
    Function resetMap,
  ) {
    // Show the bottom sheet
    showModalBottomSheet(
      clipBehavior: Clip.hardEdge,
      barrierColor: const Color.fromARGB(0, 0, 0, 0),
      context: context,
      isScrollControlled: true,
      // isDismissible: false,
      // enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
        side: BorderSide(color: ZipColors.boxBorder, width: 1.0),
      ),
      builder: (BuildContext context) {
        return FractionallySizedBox(
          heightFactor: 0.5,
          child: VehicleRideStatusConfirmationScreen(
              ride: ride, resetMap: resetMap),
        );
      },
    );
  }
}
