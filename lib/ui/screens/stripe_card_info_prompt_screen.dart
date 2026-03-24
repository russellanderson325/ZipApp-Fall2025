import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:zipapp/services/payment.dart';
import 'package:zipapp/constants/zip_colors.dart';
import 'package:zipapp/logger.dart';

class StripeCardInfoPromptScreen extends StatefulWidget {
  final Function refreshKey;

  const StripeCardInfoPromptScreen({super.key, required this.refreshKey});

  @override
  StripeCardInfoPromptScreenState createState() =>
      StripeCardInfoPromptScreenState();
}

class StripeCardInfoPromptScreenState
    extends State<StripeCardInfoPromptScreen> {
  String statusMessage = " ";
  static DateTime lastButtonPress = DateTime(0);
  static bool stripeButtonPressed = false;
  final AppLogger logger = AppLogger();

  CardFieldInputDetails? _card;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZipColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: ZipColors.primaryBackground,
        title: const Text("Add Card"),
      ),
      body: Container(
        margin: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const SizedBox(height: 200),
            Column(
              children: [
                CardField(
                  cursorColor: const Color.fromARGB(255, 54, 54, 54),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Card Information',
                  ),
                  enablePostalCode: true,
                  onCardChanged: (card) {
                    setState(() {
                      _card = card;
                      if (statusMessage == "Please enter valid card information.") {
                        statusMessage = " ";
                      }
                    });
                  },
                ),
                const SizedBox(height: 30),
                Visibility(
                  child: (statusMessage != "loading"
                      ? Text(
                          statusMessage,
                          style: const TextStyle(color: Colors.red),
                        )
                      : const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                          ),
                        )),
                ),
              ],
            ),
            const SizedBox(height: 30),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (DateTime.now().difference(lastButtonPress).inSeconds < 3) {
                  return;
                }
                lastButtonPress = DateTime.now();

                setState(() {
                  statusMessage = "loading";
                });

                if (_card?.complete != true) {
                  setState(() {
                    statusMessage = "Please enter valid card information.";
                  });
                  return;
                }

                Payment.createPaymentMethod().then((paymentMethod) async {
                  Map<String, dynamic>? paymentMethodWithFingerprint =
                      await Payment.getPaymentMethodById(paymentMethod!.id);
                  logger.info("Payment Method: $paymentMethodWithFingerprint");

                  String fingerprint =
                      paymentMethodWithFingerprint!['fingerprint'];

                  logger.info("Fingerprint: $fingerprint");

                  await Payment.setPaymentMethodIdAndFingerprint(
                      paymentMethod.id, fingerprint);

                  if (!mounted) return;

                  Navigator.pop(context);
                  widget.refreshKey();
                }).catchError((e) {
                  logger.error(e.toString());

                  if (!mounted) return;

                  switch (e.toString()) {
                    case "Exception: Payment method already exists":
                      setState(() {
                        statusMessage = "Payment method already exists.";
                      });
                      break;
                    case "Exception: Stripe customer not ready. Please log out and log back in.":
                      setState(() {
                        statusMessage =
                            "Stripe customer not ready. Please log out and log back in.";
                      });
                      break;
                    default:
                      setState(() {
                        statusMessage = "Please enter valid card information.";
                      });
                      break;
                  }
                });
              },
              child: Ink(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: const DecorationImage(
                    image: AssetImage("assets/connectstripe_blurple_4x.png"),
                    fit: BoxFit.cover,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}