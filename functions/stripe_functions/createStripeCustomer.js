const functions = require("firebase-functions");
const admin = require("firebase-admin");
const secretKey = functions.config().stripe.secret;
const stripe = require("stripe")(secretKey);

const createStripeCustomer = functions.auth.user().onCreate(async (user) => {
  try {
    const customer = await stripe.customers.create({
      email: user.email,
      metadata: { firebaseUID: user.uid },
    });

    await admin
      .firestore()
      .collection("stripe_customers")
      .doc(user.uid)
      .set({ customer_id: customer.id }, { merge: true });

    console.log("Created Stripe customer:", customer.id, "for UID:", user.uid);
  } catch (error) {
    console.error("Error creating Stripe customer:", error);
  }
});

module.exports = createStripeCustomer;
