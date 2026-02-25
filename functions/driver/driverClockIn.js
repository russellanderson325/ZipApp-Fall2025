const functions = require("firebase-functions");
const admin = require("firebase-admin");

const driverClockIn = functions.https.onCall(async (data, context) => {
    // Authentication check
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'The function must be called while authenticated.'
        );
    }

    const {daysOfWeek, driveruid, shiftuid} = data;

    // Security: Only allow users to clock in themselves
    if (context.auth.uid !== driveruid) {
        throw new functions.https.HttpsError(
            'permission-denied',
            'You can only clock in yourself.'
        );
    }

    const currentTime = new Date();
    
    // Check if driver is scheduled for today
    console.log("daysOfWeek", daysOfWeek);
    console.log("currentDay", currentTime.getDay());
    if (!daysOfWeek.includes(currentTime.getDay())) {
        return {success: false, response: "You are not scheduled to drive today."};
    }

    // Check if driver is already clocked in
    const driverDoc = await admin.firestore().collection("drivers").doc(driveruid).get();
    if (driverDoc.exists && driverDoc.data().isWorking) {
        return {success: false, response: "You are already clocked in."};
    }

    // Get or create shift
    const shiftRef = await admin.firestore()
        .collection("drivers")
        .doc(driveruid)
        .collection("shifts")
        .doc(shiftuid)
        .get();

    if (!shiftRef.exists) {
        await createShift(driveruid, shiftuid, currentTime);
    }

    try {
        await updateShiftAndDriverStatus(driveruid, shiftuid, currentTime);
        console.log("Driver clocked in successfully:", driveruid);
        return {success: true, response: "Clock in successful."};
    } catch (error) {
        console.error("Clock in error:", error);
        throw new functions.https.HttpsError('internal', 'Failed to clock in. Please try again.');
    }
});

/**
 * Create a new shift for the driver
 * @param {string} driveruid - The driver's uid
 * @param {string} shiftuid - The shift's uid
 * @param {Date} currentTime - The current time
 * @return {Promise<void>}
 */
async function createShift(driveruid, shiftuid, currentTime) {
    await admin.firestore()
        .collection("drivers")
        .doc(driveruid)
        .collection("shifts")
        .doc(shiftuid)
        .set({
            shiftStart: currentTime,
            shiftEnd: currentTime,
            startTime: currentTime,
            endTime: currentTime,
            totalShiftTime: 0,
            totalBreakTime: 0,
            breakStart: currentTime,
            breakEnd: currentTime,
            overrideNeeded: false,
        });
}

/**
 * Update the driver's shift and status
 * @param {string} driveruid
 * @param {string} shiftuid
 * @param {Date} currentTime
 * @return {Promise<void>}
 */
async function updateShiftAndDriverStatus(driveruid, shiftuid, currentTime) {
    await admin.firestore()
        .collection("drivers")
        .doc(driveruid)
        .collection("shifts")
        .doc(shiftuid)
        .update({
            totalBreakTime: 0,
            totalShiftTime: 0,
            shiftStart: currentTime,
            overrideNeeded: false,
        });

    await admin.firestore()
        .collection("drivers")
        .doc(driveruid)
        .update({
            isWorking: true,
            isAvailable: true,
            isOnBreak: false,
        });
}

module.exports = driverClockIn;