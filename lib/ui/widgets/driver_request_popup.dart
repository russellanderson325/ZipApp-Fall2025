import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zipapp/models/request.dart';
import 'package:zipapp/business/drivers.dart';
import 'package:zipapp/constants/zip_design.dart';
import 'package:zipapp/constants/zip_colors.dart';


class RideRequestPopup extends StatefulWidget {
  final Request request;
  final VoidCallback onDismiss;

  const RideRequestPopup({
    super.key,
    required this.request,
    required this.onDismiss,
  });

  @override
  State<RideRequestPopup> createState() => _RideRequestPopupState();
}

class _RideRequestPopupState extends State<RideRequestPopup> {
  final DriverService _driverService = DriverService();
  late int _secondsRemaining;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = 10;
    _startCountdown();
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
        _startCountdown();
      }
    });
  }

  Future<void> _handleAccept() async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      await _driverService.acceptRequest(widget.request.id);
      widget.onDismiss();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error accepting request: $e');
      }
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept ride: $e')),
        );
      }
    }
  }

  String _formatPrice(dynamic price) {
  if (price is String) {
    final parsedPrice = double.tryParse(price);
    if (parsedPrice != null) {
      return '\$${parsedPrice.toStringAsFixed(2)}';  // Added $ symbol
    }
    return price;
  } else if (price is num) {
    return '\$${price.toStringAsFixed(2)}';  // Added $ symbol
  }
  return '\$0.00';
}

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ZipColors.boxBorder, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with close button
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Model badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                     child: Row(
    children: [
      // Show cart image based on model
      Image.asset(
        widget.request.model == 'X' 
          ? 'assets/XCart.png' 
          : 'assets/XLCart.png',
        width: 20,
        height: 20,
        color: Colors.white,
      ),
      const SizedBox(width: 6),
      Text(
        'Model ${widget.request.model}',
        style: ZipDesign.bodyText.copyWith(
          color: Colors.white,
          fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Close button (but disabled)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, size: 20, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              
              // Price - Large and prominent
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _formatPrice(widget.request.price),
                  style: ZipDesign.pageTitleText.copyWith(
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Trip details
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pickup
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '[Time and Miles away]',
                                style: ZipDesign.bodyText.copyWith(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pick Up Address',
                                style: ZipDesign.bodyText.copyWith(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Dropoff
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.rectangle,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '[Time and Miles away]',
                                style: ZipDesign.bodyText.copyWith(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Drop Off Address',
                                style: ZipDesign.bodyText.copyWith(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Accept button
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _handleAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZipColors.zipYellow,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Accept',
                            style: ZipDesign.labelText.copyWith(
                              color: Colors.black,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ),
              ),
              
              // Timer at bottom
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Auto-declining in $_secondsRemaining seconds',
                    style: ZipDesign.bodyText.copyWith(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper function to show the ride request popup
void showRideRequestPopup(BuildContext context, Request request, VoidCallback onDismiss) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => RideRequestPopup(
      request: request,
      onDismiss: onDismiss,
    ),
  );
}