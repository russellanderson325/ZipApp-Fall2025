import 'package:flutter/material.dart';
import 'package:zipapp/constants/zip_colors.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZipColors.primaryBackground,
        body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text('Privacy Policy Screen'),
          // go back text button
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: ZipColors.submittedYellowBorder, // text color
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
            ),
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text(
              'Go Back',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
            ),
          ),
        ],
      ),
    ));
  }
}
