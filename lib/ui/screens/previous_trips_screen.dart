import "package:flutter/material.dart";
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:zipapp/business/user.dart';
import 'package:zipapp/constants/zip_colors.dart';
import 'package:zipapp/logger.dart';

class PreviousTripsScreen extends StatefulWidget {
  const PreviousTripsScreen({super.key});

  @override
  State<PreviousTripsScreen> createState() => _PreviousTripsScreenState();
}

class _PreviousTripsScreenState extends State<PreviousTripsScreen> {
  late VoidCallback onBackPress;
  final UserService userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  late List<QueryDocumentSnapshot> pastRidesList;
  List<dynamic> pastRideIDs = [];
  late DocumentReference rideReference;
  final AppLogger logger = AppLogger();

  @override
  void initState() {
    onBackPress = () {
      Navigator.of(context).pop();
    };
    super.initState();
  }

  Future<List<String>> _retrievePastRideIDs() async {
    try {
      DocumentReference userRef =
          _firestore.collection('users').doc(userService.userID);
      
      DocumentSnapshot snapshot = await userRef.get();
      
      if (!snapshot.exists) {
        logger.warning('User document not found for ${userService.userID}');
        pastRideIDs = [];
        return [];
      }
      
      // Safely get pastRides field with null handling
      pastRideIDs = List<String>.from(snapshot.get('pastRides') ?? []);
      
      logger.info('Retrieved ${pastRideIDs.length} past ride IDs');
      return pastRideIDs as List<String>;
    } catch (e) {
      logger.error('Error retrieving past rides: $e');
      pastRideIDs = [];
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text(
            'Past Trips',
          ),
        ),
        body: FutureBuilder<List<String>>(
            future: _retrievePastRideIDs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading trips: ${snapshot.error}'),
                );
              }
              
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('No past trips found'),
                );
              }
              
              return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    return Container(
                      height: 50,
                      color: ZipColors.zipYellow,
                      child: Center(
                          child: Text('past ride: ${snapshot.data![index]}')),
                    );
                  });
            }));
  }
}