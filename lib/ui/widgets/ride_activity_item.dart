import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:zipapp/constants/tailwind_colors.dart';
import 'package:zipapp/constants/zip_design.dart';
import 'package:zipapp/constants/zip_formats.dart';
import 'package:zipapp/ui/screens/ride_details_screen.dart';

class RideActivityItem extends StatefulWidget {
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
  const RideActivityItem(
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
  State<RideActivityItem> createState() => _RideActivityItemState();
}

class _RideActivityItemState extends State<RideActivityItem> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: TailwindColors.gray300)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RideDetailsScreen(
                        startTime: widget.startTime,
                        price: widget.price,
                        origin: widget.origin,
                        destination: widget.destination,
                        endTime: widget.endTime,
                        id: widget.id,
                        tip: widget.tip,
                        rating: widget.rating,
                        status: widget.status,
                        cardUsed: widget.cardUsed,
                        last4: widget.last4,
                        paymentMethod: widget.paymentMethod),
                  ),
                );
              },
              style: ButtonStyle(
                padding: MaterialStateProperty.all(const EdgeInsets.all(0)),
                foregroundColor: MaterialStateProperty.all(Colors.black),
                textStyle: MaterialStateProperty.all(ZipDesign.labelText),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.destination),
                      ZipFormats.activityDateFormatter(widget.endTime)
                    ],
                  ),
                  Row(children: <Widget>[
                    Text(
                      "\$${widget.price.toStringAsFixed(2)}",
                      style: ZipDesign.disabledBodyText,
                    ),
                    const SizedBox(width: 16),
                    const Icon(LucideIcons.chevronRight,
                        size: 24, color: TailwindColors.gray500),
                  ])
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
