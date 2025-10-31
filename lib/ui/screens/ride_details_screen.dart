import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:zipapp/business/user.dart';
import 'package:zipapp/constants/tailwind_colors.dart';
import 'package:zipapp/constants/zip_colors.dart';
import 'package:zipapp/constants/zip_design.dart';
import 'package:zipapp/constants/zip_formats.dart';
import 'package:zipapp/ui/widgets/rating_drawer.dart';
import 'package:zipapp/logger.dart';

class RideDetailsScreen extends StatefulWidget {
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
  const RideDetailsScreen(
      {super.key,
      required this.destination,
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

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  final AppLogger logger = AppLogger();
  final UserService userService = UserService();
  final DraggableScrollableController scrollController =
      DraggableScrollableController();

  final int drawerDelayMS = 400;
  bool submitted = false;

  late void Function() clearData;

  late String tip;
  late String rating;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(() {
      if (scrollController.size == 0 && !getSubmitted()) {
        clearData();
      }
    });
    // tip = 'No tip added';
    tip = '0';
    // rating = 'No rating';
    rating = '0';
    // _updateTipAndRating();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Details', style: ZipDesign.pageTitleText),
        backgroundColor: ZipColors.primaryBackground,
        titleSpacing: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          padding: const EdgeInsets.all(0),
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      backgroundColor: ZipColors.primaryBackground,
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildNameDatePriceRow(),
                    const Padding(
                      padding: EdgeInsets.only(top: 32, bottom: 16),
                      child: Text(
                        'Location',
                        textAlign: TextAlign.left,
                        style: ZipDesign.sectionTitleText,
                      ),
                    ),
                    _buildStartLocation(
                      widget.origin,
                      widget.startTime,
                    ),
                    const SizedBox(height: 16),
                    _buildEndLocation(
                      widget.destination,
                      widget.endTime,
                    ),
                    widget.status != "CANCELED"
                        ? const Padding(
                            padding: EdgeInsets.only(top: 32, bottom: 16),
                            child: Text(
                              'Ride Status',
                              textAlign: TextAlign.left,
                              style: ZipDesign.sectionTitleText,
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.only(top: 32, bottom: 16),
                            child: Text(
                              'This Ride was Canceled.',
                              textAlign: TextAlign.left,
                              style: ZipDesign.sectionTitleText,
                            ),
                          ),
                    _buildTipRow(
                      LucideIcons.coins,
                      widget.tip,
                      'Add tip',
                      widget.status,
                    ),
                    const SizedBox(height: 16),
                    _buildRatingRow(
                      LucideIcons.star,
                      widget.rating,
                      'Rate',
                      widget.status,
                    ),
                    widget.status != "CANCELED"
                        ? const Padding(
                            padding: EdgeInsets.only(top: 32, bottom: 16),
                            child: Text(
                              'Payment',
                              textAlign: TextAlign.left,
                              style: ZipDesign.sectionTitleText,
                            ),
                          )
                        : const SizedBox(),
                    _buildPaymentRow(
                        LucideIcons.creditCard,
                        widget.cardUsed,
                        widget.last4,
                        widget.price,
                        widget.paymentMethod,
                        widget.status),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('Trip ID: ${widget.id}',
                      style: ZipDesign.tinyLightText),
                ),
              ],
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.0,
            controller: scrollController,
            minChildSize: 0.0,
            maxChildSize: 1,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                child: RatingDrawer(
                  closeDrawer: hideDrawer,
                  getSubmitted: getSubmitted,
                  setSubmitted: setSubmitted,
                  builder:
                      (BuildContext context, void Function() methodFromChild) {
                    clearData = methodFromChild;
                  },
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: const SizedBox(height: 0.0, width: 0.0),
    );
  }

  bool getSubmitted() {
    return submitted;
  }

  void setSubmitted(bool value) {
    setState(() {
      submitted = value;
    });
    if (value) {
      _updateTipAndRating();
    }
  }

  Widget _buildNameDatePriceRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ride with ${userService.user.firstName} ${userService.user.lastName[0]}.',
              textAlign: TextAlign.left,
              style: ZipDesign.sectionTitleText,
            ),
            ZipFormats.activityDetailsDatePriceFormatter(
                widget.endTime, widget.price),
          ],
        ),
        Container(
          height: 56,
          width: 56,
          decoration: BoxDecoration(
            color: TailwindColors.gray300,
            borderRadius: BorderRadius.circular(100),
          ),
          child: const Icon(LucideIcons.user,
              color: TailwindColors.gray500, size: 24),
        )
      ],
    );
  }

  Widget _buildStartLocation(String address, DateTime dateTime) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(LucideIcons.locate, size: 16, color: Colors.black),
            const SizedBox(width: 16),
            Text(address,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w400)),
          ],
        ),
        ZipFormats.activityDetailsTimeFormatter(dateTime),
      ],
    );
  }

  Widget _buildEndLocation(String address, DateTime dateTime) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(LucideIcons.mapPin, size: 16, color: Colors.black),
            const SizedBox(width: 16),
            Text(address,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w400)),
          ],
        ),
        ZipFormats.activityDetailsTimeFormatter(dateTime),
      ],
    );
  }

  Widget _buildTipRow(
      IconData icon, double tip, String buttonTitle, String status) {
    if (status == "CANCELED" || status == "IN_PROGRESS") {
      return const Row();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: <Widget>[
          Icon(icon, size: 16, color: Colors.black),
          const SizedBox(width: 16),
          Text(
            status != "CANCELED" || status != "IN_PROGRESS"
                ? tip.toString()
                : '0',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
          ),
        ]),
        SizedBox(
          height: 23,
          width: 64,
          child: TextButton(
            onPressed: showDrawer,
            style: ButtonStyle(
              fixedSize: WidgetStateProperty.all(const Size(64, 23)),
              padding: WidgetStateProperty.all(const EdgeInsets.all(0)),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              backgroundColor:
                  WidgetStateProperty.all(TailwindColors.gray200),
            ),
            child: Text(
              buttonTitle,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                fontFamily: 'Lexend',
                color: Colors.black,
              ),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildRatingRow(
      IconData icon, int value, String buttonTitle, String status) {
    if (status == "CANCELED" || status == "IN_PROGRESS") {
      return const Row();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: <Widget>[
          Icon(icon, size: 16, color: Colors.black),
          const SizedBox(width: 16),
          Text(
            value.toString(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
          ),
        ]),
        SizedBox(
          height: 23,
          width: 64,
          child: TextButton(
            onPressed: showDrawer,
            style: ButtonStyle(
              fixedSize: WidgetStateProperty.all(const Size(64, 23)),
              padding: WidgetStateProperty.all(const EdgeInsets.all(0)),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              backgroundColor:
                  WidgetStateProperty.all(TailwindColors.gray200),
            ),
            child: Text(
              buttonTitle,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                fontFamily: 'Lexend',
                color: Colors.black,
              ),
            ),
          ),
        )
      ],
    );
  }

  /*
  * TODO: Implement _getRideTip
  Future<void> _getRideTip() async {
    try {
      var ratingCollection = _firestore.collection('ratings');
      var rideTip = await ratingCollection.doc(widget.id).get();
      if (rideTip.exists && rideTip.data() != null) {
        Map<String, dynamic> data = rideTip.data() as Map<String, dynamic>;
        if (data.containsKey('tip')) {
          setState(() {
            tip = data['tip'].toDouble();
          });
        }
      }
    } catch (e) {
      print(
          "Error loading default tip percentage, using local default instead: $e");
    }
  }
  */

 
  /*
  * TODO: Implement _getRideRating
  Future<void> _getRideRating() async {
    try {
      var ratingCollection = _firestore.collection('ratings');
      var userDoc = await ratingCollection.doc(userService.user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
        if (data.containsKey('rating')) {
          setState(() {
            tip = data['rating'].toDouble();
          });
        }
      }
    } catch (e) {
      print(
          "Error loading default tip percentage, using local default instead: $e");
    }
  }
  */

  void _updateTipAndRating() {
    setState(() {
      tip = '1';
      rating = '1';
    });
    // _getRideTip();
    // _getRideRating();
  }

  void showDrawer() {
    scrollController.animateTo(1,
        duration: Duration(milliseconds: drawerDelayMS),
        curve: Curves.easeInOut);
  }

  void hideDrawer() {
    scrollController.animateTo(0.0,
        duration: Duration(milliseconds: drawerDelayMS),
        curve: Curves.easeInOut);
  }

  Widget _buildPaymentRow(IconData icon, String? cardName, String? last4,
      double price, String? paymentMethod, String status) {
    if (kDebugMode) {
      print(paymentMethod);
    }
    if (status == "CANCELED" || status == "IN_PROGRESS") {
      return const Row();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Row(
          children: <Widget>[
            paymentMethod != null
                ? (paymentMethod == 'apple_pay'
                    ? Image.asset('assets/apple_pay_icon.png',
                        width: 50, height: 30)
                    : const Icon(LucideIcons.creditCard,
                        size: 16, color: Colors.black))
                : const Icon(LucideIcons.creditCard,
                    size: 16, color: Colors.black),
            const SizedBox(width: 16),
            Text(
                cardName ??
                    (paymentMethod == 'apple_pay'
                        ? "Apple Pay"
                        : paymentMethod == "google_pay"
                            ? "Google Pay"
                            : "Unknown Method"),
                style: ZipDesign.bodyText),
          ],
        ),
        Text(
          '\$$price',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              fontFamily: 'Lexend',
              color: TailwindColors.gray500),
        )
      ],
    );
  }
}
