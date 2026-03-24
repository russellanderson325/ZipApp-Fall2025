const functions = require("firebase-functions");
const secretKey = functions.config().stripe.secret;
const stripe = require("stripe")(secretKey);

const createPaymentIntent = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "The function must be called while authenticated."
    );
  }

  try {
    const { amount, currency, customerId, paymentMethodId } = data;

    if (!amount || !currency) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "amount and currency are required."
      );
    }

    let paymentIntent;

    // Saved card flow
    if (customerId && paymentMethodId) {
      paymentIntent = await stripe.paymentIntents.create({
        amount,
        currency,
        customer: customerId,
        payment_method: paymentMethodId,
        confirm: true,
        off_session: true,
        capture_method: "manual",
      });
    } else {
      // Apple Pay / Google Pay / payment sheet flow
      paymentIntent = await stripe.paymentIntents.create({
        amount,
        currency,
        capture_method: "manual",
      });
    }

    return {
      success: true,
      response: paymentIntent,
    };
  } catch (error) {
    console.error("Stripe error:", error);

    return {
      success: false,
      response: {
        message: error.message || "Unknown Stripe error",
        code: error.code || "unknown",
        type: error.type || "unknown",
      },
    };
  }
});

module.exports = createPaymentIntent;