const functions = require("firebase-functions");
const secretKey = functions.config().stripe.secret;
const stripe = require("stripe")(secretKey);

const getPaymentMethodDetails = functions.https.onCall(async (data, context) => {
    // Ensure the user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "The function must be called while authenticated.",
        );
    }

    try {
        const paymentMethodId = data.paymentMethodId; // Expect "paymentMethodId" to be passed in the function call

        if (!paymentMethodId) {
            throw new functions.https.HttpsError(
                "invalid-argument", "paymentMethodId is required.",
            );
        }

        const paymentMethod = await stripe.paymentMethods.retrieve(paymentMethodId);

        return {
            success: true,
            response: {
                brand: paymentMethod.card?.brand ?? paymentMethod.type,
                last4: paymentMethod.card?.last4 ?? "",
                exp_month: paymentMethod.card?.exp_month ?? null,
                exp_year: paymentMethod.card?.exp_year ?? null,
                fingerprint: paymentMethod.card?.fingerprint ?? null,
                type: paymentMethod.type,
            },
        };

    } catch (error) {
        console.error("Stripe error:", error.message, "| Code:", error.code);
        
        throw new functions.https.HttpsError(
            "internal",
            error.message ?? "Failed to retrieve payment method.",
            { code: error.code}
        );
    }
});

module.exports = getPaymentMethodDetails;
