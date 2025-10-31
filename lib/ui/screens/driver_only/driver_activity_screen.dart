import 'package:flutter/material.dart';
import 'package:zipapp/constants/zip_design.dart';
import 'package:zipapp/ui/screens/driver_only/driver_activity_item.dart';

class DriverActivityScreen extends StatefulWidget {
  const DriverActivityScreen({super.key});

  @override
  State<DriverActivityScreen> createState() => _DriverActivityScreenState();
}

class _DriverActivityScreenState extends State<DriverActivityScreen> {
  List<Ride> rides = [];
  double averageRating = 0;

  @override
  void initState() {
    super.initState();
    // TODO: Load real ride data from Firebase
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Activity',
          style: ZipDesign.pageTitleText,
        ),
        scrolledUnderElevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '\nYour Average Rating',
              style: ZipDesign.sectionTitleText,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 40),
                const SizedBox(width: 10),
                RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                        text: averageRating.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.black, fontSize: 28),
                      ),
                      const TextSpan(
                        text: ' / 5.0',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(
              color: Colors.grey,
              thickness: 0.5,
            ),
            const SizedBox(height: 16),
            const Text(
              'Completed Trips',
              style: ZipDesign.sectionTitleText,
            ),
            Expanded(
              child: rides.isEmpty
                  ? const Center(child: Text('No completed trips yet'))
                  : ListView.builder(
                      itemCount: rides.length,
                      itemBuilder: (context, index) {
                        return DriverActivityItem(
                          destination: rides[index].destination,
                          dateTime: rides[index].dateTime,
                          price: rides[index].price,
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}

class Ride {
  final String destination;
  final DateTime dateTime;
  final double price;
  final double rating;

  Ride({
    required this.destination,
    required this.dateTime,
    required this.price,
    this.rating = 5.0,
  });
}