const functions = require("firebase-functions");
const secretKey = functions.config().stripe.secret;
const stripe = require("stripe")(secretKey);



const attachPaymentMethodToCustomer = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "The function must be called while authenticated.",
        );
    }

     console.log("Incoming data:", JSON.stringify(data));

    console.log("Attaching payment method:", data.paymentMethodId, "to customer:", data.customerId);
    if (!data.paymentMethodId || !data.customerId) {
        throw new functions.https.HttpsError(
            "invalid-argument", "paymentMethodId and customerId are required.",
        );
    }

    const paymentMethod = await stripe.paymentMethods.attach(
        data.paymentMethodId,
        { customer: data.customerId },
    );

    console.log("Payment method attached successfully:", paymentMethod.id);
    return { success: true, response: paymentMethod};
});

module.exports = attachPaymentMethodToCustomer;
