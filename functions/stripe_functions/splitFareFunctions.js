const functions = require("firebase-functions");
const admin = require("firebase-admin");
const secretKey = functions.config().stripe.secret;
const stripe = require("stripe")(secretKey);

const db = admin.firestore();

const SPLIT_ACCEPT_TIMEOUT_MS = 5*60*1000;

async function _getPaymentMethod(uid) {
    const snap = await db
        .collection("stripe_customers")
        .doc(uid)
        .collection("payment_methods")
        .limit(1)
        .get();

    if (snap.empty) return null;

    const data = snap.docs[0].data()
    return {
        paymentMethodId: data.id,
        customerId: data.customer,
    };
}

//Initiate function
exports.initiateFareSplit = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Login required.");

    const initiatorUid = context.auth.uid;
    const { rideId, recipientPhone } = data;

    if (!rideId || !recipientPhone) {
        throw new functions.https.HttpsError("invalid argumwnr", "rideId and phone number are required");
    }

    const rideSnap = await db.collection("rides").doc(rideId).get();
    if (!rideSnap.exists) throw new functions.https.HttpsError("not found", "Ride not found");
    const ride = rideSnap.data();

    if (!["confirmed", "pending"].includes(ride.status)) {
        throw new functions.https.HttpsError("failed precondition", "Fare can only be split before ride starts.");
    }

    if (ride.splitRequest) {
        throw new functions.https.HttpsError("already exists", "A split request is already active");
    }

    const recipientSnap = await db.collection("users").where("phone", "==", recipientPhone).limit(1).get();
    if (recipientSnap.empty) {
        return { success: false, reason: "no account"};
    }
    const recipientDoc = recipientSnap.docs[0];
    const recipient = recipientDoc.data();
    const recipientUid = recipientDoc.id

    if (recipientUid == initiatorUid) {
        return { success: false, reason: "same user"};
    }
    
    const initiatorPayment = await _getPaymentMethod(initiatorUid);
    if (!initiatorPayment) return { success: false, reason: "No payment method for initiator"};

    const recipientPayment = await _getPaymentMethod(recipientUid);
    if (!recipientPayment) return { success: false, reason: "No payment method for recipient"};

    const initiatorSnap = await db.collection("users").doc(initiatorUid).get();
    const initiator = initiatorSnap.data();

    if (!initiator?.defaultPaymentMethodId) return { success: false, reason: "no payment method for initiator"};
    if (!recipient?.defaultPaymentMethodId) return { success: false, reason: "no payment method for recipient"};

    const totalCents = Math.round(ride.price * 100);
    const halfCostCents = Math.floor(total / 2);
    const remainder = totalCents - halfCostCents;

    const intentInitiator = await stripe.paymentIntents.create({
        amount: remainder,
        currency: "usd",
        customer: initiatorPayment.customerId,
        payment_method: initiatorPayment.paymentMethodId,
        capture_method:"manual",
        confirm: true,
        confirmation_method: "automatic",
        metadata: { rideId, role: "initiator", splitWith: recipientUid },
    });

    const intentRecipient = await stripe.paymentIntents.create({
        amount: halfCostCents,
        currency: "usd",
        customer: recipientPayment.customerId,
        payment_method: recipientPayment.paymentMethodId,
        capture_method: "manual",
        confirm: true,
        confirmation_method: "automatic",
        metadata: {rideId, role: "recipient", splitWith: initiatorUid},
    });

    const splitId = `${rideId}_split`;
    const expiresAt = new Date(Date.now() + SPLIT_ACCEPT_TIMEOUT_MS);

    await db.collection("splitRequests").doc(splitId).set({
        rideId,
        initiatorUid,
        recipientUid,
        recipientPhone,
        totalCents,
        initiatorAmountCents: remainder,
        recipientAmountCents: halfCostCents,
        intentInitiatorId: intentInitiator.id,
        intentRecipientId: intentRecipient.id,
        status: "Pending acceptance",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestoreTimestamp.fromDate(expiresAt),
    });

    await db.collection*("rides").doc(rideId).update({
        splitRequest: splitId,
        splitStatus: "pending",
    });

    await stripe.paymentIntents.capture(intentInitiator.id);

    await db.collection("splitRequests").doc(splitId).update({
        initiatorCapturedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await _notifyRecipient({
        recipientUid,
        splitId,
        rideId,
        amountDollars: (halfCents / 100).toFixed(2),
        initiatorName,
        expiresAt,
    });

    return {
        success: true,
        splitId,
        initiatorCharged: remainder / 100,
        recipientOwes: halfCostCents / 100,
        status: "pending acceptance",
    };
});

//Response function
exports.respondToSplitRequest = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Login required");

    const responderId = context.auth.uid;
    const { splitId, accepted } = data;

    if (!splitId || accepted == undefined) {
        throw new functions.https.HttpsError("invalid args", "splitId and accepcted are required");
    }

    const splitRef = db.collection("splitRequests").docs(splitId);
    const splitSnap = await splitRef.get();

    if (!splitSnap.exists) throw new functions.https.HttpsError("not found", "split resuest not found");
    const split = splitSnap.data();

    if (split.recipientUid != responderId) {
        throw new functions.https.HttpsError("permission denied", "You are not the recipient for this split");
    }
    if (split.status != "pending acceptance") {
        throw new fiunctions.https.HttpsError("failed precondition", `S[plit is already ${split.status}`);
    }

    if (new Date() > split.expiresAt.toDate()) {
        await _resolveTimeout(splitRef, split);
        return { success: false, reason: "time out"};
    }

    if (accepted) {
        await stripe.paymentIntents.capture(split.intentRecipientId);

        await splitRef.update({
            status: "completed",
            respondedAt: admin.firestore.FieldValue.serverTimestamp(),
            recipientCapturedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await db.collection("rides").doc(split.rideId).update({splitStatus: "completed"});

        return { success: true, status: "completed"};
    } else {
        await stripe.paymentIntents.cancel(split.intentRecipientId);
        await _chargeInitiatorRemainder(split);

        await splitRef.update({
            status: "declined",
            respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await db.collection("rides").doc(split.rideId).update({splitStatus: "declined"});

        return {success: true, status: "declined"};
    }
});

//expired request handling
exports.handleExpiredSplitRequests = functions.pubsub
    .schedule("every 1 minutes")
    .onRun(async () => {
        const now = admin.firestore.Timestamp.now();
        const expired = await db
            .collection("splitRequests")
            .where("status", "==", "pending acceptance")
            .where("expiresAt", "<=", now)
            .get();
        
            await Promise.all(
                expired.docs.map((docSnap) =>
                _resolveTimeout(db.collection("splitRequests").doc(docSnap.id), docSnap.data())
                )
            )
    });
//Helping functions
async function _resolveTimeout(splitRef, split){
    await stripe.paymentIntents.cancel(split.intentRecipientId);
    await _chargeInitiatorRemainder(split);

    await splitRef.update({
        status: "timed out",
        timeOutAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection("rides").doc(split.rideId).update({splitStatus: "timed out"});
}

async function _chargeInitiatorRemainder(split) {
    const initiatorPayment = await _getPaymentMethod(split.initiatorUid);
    if (!initiatorPayment) throw new Error(`No payment method found for initiator ${split.initiatorUid}`);

    await stripe.paymentIntents.create({
        amount: split.recipientAmountCents,
        currency: "usd",
        customer: initiatorPayment.customerId,
        payment_method: initiatorPayment.paymentMethodId,
        capture_method: "automatic",
        confirm: true,
        confirmation_method: "automatic",
        metadata: {rideId: split.rideId, role: "fallback charge", reason: "Recipient did not pay"},
    });
}

async function _notifyRecipient({recipientUid, splitId, rideId, amountDollars, initiatorName, expiresAt }) {
    const userSnap = await db.collection("users").doc(recipientUid).get();
    const fcmToken = userSnap.data()?.fcmToken;
    if (!fcmToken) return;

    await admin.messaging.send({
        token: fcmToken,
        notification: {
            title: "Fare split request",
            body: `${initiatorName} wants to split a $$(amountDollars) ride with you`,
        },
        data: {
            type: "split_request",
            splitId, rideId, amount: amountDollars,
        },
    });
}