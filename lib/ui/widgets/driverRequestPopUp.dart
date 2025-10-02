import 'package:flutter/material.dart';
import 'package:zipapp/models/request.dart';
import 'package:zipapp/business/drivers.dart';

/// Minimalistic Uber-style ride request popup
class RideRequestPopup extends StatefulWidget {
  final Request request;
  final VoidCallback onDismiss;

  const RideRequestPopup({
    Key? key,
    required this.request,
    required this.onDismiss,
  }) : super(key: key);

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
    _secondsRemaining = widget.request.timeout.seconds - DateTime.now().millisecondsSinceEpoch ~/ 1000;
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
      print('Error accepting request: $e');
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

  Future<void> _handleDecline() async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      await _driverService.declineRequest(widget.request.id);
      widget.onDismiss();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error declining request: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  String _formatPrice(dynamic price) {
    if (price is String) {
      final parsedPrice = double.tryParse(price);
      if (parsedPrice != null) {
        return parsedPrice.toStringAsFixed(2);
      }
      return price;
    } else if (price is num) {
      return price.toStringAsFixed(2);
    }
    return '0.00';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Timer at top
              Text(
                '$_secondsRemaining',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  color: _secondsRemaining <= 5 ? Colors.red : Colors.black87,
                  height: 1,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Rider name
              Text(
                widget.request.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Model
              Text(
                'Model ${widget.request.model}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w400,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Price
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '\$${_formatPrice(widget.request.price)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Accept button (full width)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _handleAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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
                      : const Text(
                          'Accept',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Decline button (text only)
              TextButton(
                onPressed: _isProcessing ? null : _handleDecline,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Decline',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
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