const functions = require("firebase-functions");
const admin = require("firebase-admin");
const stripe = require("stripe")(process.env.STRIPE_SECRET_KEY);

exports.createStripeCustomerCallable = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "User not authenticated");
    }

    const uid = context.auth.uid;

    const userDoc = await admin.firestore()
      .collection("users")
      .doc(uid)
      .get();

    const email = userDoc.data()?.email || "";

    // 🔥 Create Stripe customer
    const customer = await stripe.customers.create({
      email: email,
      metadata: { uid: uid },
    });

    // 💾 Save to Firestore
    await admin.firestore()
      .collection("stripe_customers")
      .doc(uid)
      .set({
        customer_id: customer.id,
      }, { merge: true });

    return {
      success: true,
      customerId: customer.id,
    };

  } catch (error) {
    console.error("Error creating Stripe customer:", error);

    throw new functions.https.HttpsError(
      "internal",
      "Failed to create Stripe customer",
      error.message
    );
  }
});