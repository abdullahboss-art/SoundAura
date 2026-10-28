

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();

const MERCHANT_ID = defineSecret('JAZZCASH_MERCHANT_ID');
const PASSWORD = defineSecret('JAZZCASH_PASSWORD');
const SALT = defineSecret('JAZZCASH_SALT');

// Sandbox. Live jaane par portal wala production URL lagayen.
const API_URL =
  'https://sandbox.jazzcash.com.pk/ApplicationAPI/API/Payment/DoTransaction';

// Server khud amount tay karta hai: app ke bheje hue amount par bharosa nahi.
// premium_service.dart ke monthlyAmount / yearlyAmount se bilkul same rakhein.
const PLANS = {
  monthly: 299, // <-- apni asli qeemat likhein
  yearly: 2499, // <-- apni asli qeemat likhein
};

function pkTime(offsetMs = 0) {
  // yyyyMMddHHmmss, Pakistan time (UTC+5)
  return new Date(Date.now() + 5 * 3600 * 1000 + offsetMs)
    .toISOString()
    .replace(/[-:T]/g, '')
    .slice(0, 14);
}

// HMAC-SHA256: salt + '&' + (khali nahi wali pp_* values, key ke hisaab se sorted, '&' se joined)
function secureHash(fields, salt) {
  const joined = Object.keys(fields)
    .filter((k) => k !== 'pp_SecureHash' && fields[k] !== '')
    .sort()
    .map((k) => fields[k])
    .join('&');
  return crypto
    .createHmac('sha256', salt)
    .update(`${salt}&${joined}`)
    .digest('hex')
    .toUpperCase();
}

exports.jazzcashWalletPay = onCall(
  { secrets: [MERCHANT_ID, PASSWORD, SALT], timeoutSeconds: 90 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Pehle login karein.');
    }
    const uid = request.auth.uid;
    const { amountPkr, mobile } = request.data || {};

    if (!/^03\d{9}$/.test(String(mobile || ''))) {
      throw new HttpsError('invalid-argument', 'Wallet number sahi nahi.');
    }

    // Amount se plan pehchano; kuch aur ho to rad.
    const plan = Object.keys(PLANS).find((p) => PLANS[p] === Number(amountPkr));
    if (!plan) {
      throw new HttpsError('invalid-argument', 'Amount sahi nahi.');
    }

    const txnRef = `T${pkTime()}${Math.floor(Math.random() * 900 + 100)}`;

    const fields = {
      pp_Version: '1.1',
      pp_TxnType: 'MWALLET',
      pp_Language: 'EN',
      pp_MerchantID: MERCHANT_ID.value(),
      pp_SubMerchantID: '',
      pp_Password: PASSWORD.value(),
      pp_BankID: 'TBANK',
      pp_ProductID: 'RETL',
      pp_TxnRefNo: txnRef,
      pp_Amount: String(PLANS[plan] * 100), // sab se chhoti ikai (paisa)
      pp_TxnCurrency: 'PKR',
      pp_TxnDateTime: pkTime(),
      pp_BillReference: 'melodyhub',
      pp_Description: `MelodyHub Premium ${plan}`,
      pp_TxnExpiryDateTime: pkTime(3600 * 1000),
      pp_ReturnURL: 'https://example.com/jazzcash-return', // portal wala URL
      ppmpf_1: String(mobile),
      ppmpf_2: '',
      ppmpf_3: '',
      ppmpf_4: '',
      ppmpf_5: '',
    };
    fields.pp_SecureHash = secureHash(fields, SALT.value());

    let body;
    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(fields),
      });
      body = await res.json();
    } catch (e) {
      console.error('JazzCash request failed', e);
      throw new HttpsError('unavailable', 'JazzCash se rabta nahi ho saka.');
    }

    // "000" = kamyab. Baaki codes ke liye portal ki list dekhein.
    const ok = body && body.pp_ResponseCode === '000';

    if (ok) {
      // Premium yahin server par likhein: app par bharosa nahi.
      const days = plan === 'yearly' ? 365 : 30;
      await admin
        .firestore()
        .doc(`users/${uid}/premium/status`)
        .set({
          plan,
          txnRef,
          active: true,
          expiry: admin.firestore.Timestamp.fromMillis(
            Date.now() + days * 24 * 3600 * 1000
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    return {
      ok,
      txnRef,
      message: ok
        ? 'Payment kamyab.'
        : body?.pp_ResponseMessage || 'Payment nahi ho saki.',
    };
  }
);
