// Soulo Stripe Backend — Cloud Function (Node.js + Stripe SDK)
// Deploy to Vercel, Netlify, or AWS Lambda.
// Set env vars: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, PRICE_MONTHLY, PRICE_ANNUAL

const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

// CORS headers
const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// Price IDs (set these in your Stripe Dashboard)
const PRICES = {
  monthly: process.env.PRICE_MONTHLY || 'price_monthly_9_99',
  annual: process.env.PRICE_ANNUAL || 'price_annual_79_99',
};

// POST /create-checkout-session
async function createCheckoutSession(body) {
  const { priceId, customerEmail, successUrl, cancelUrl, metadata } = body;

  if (!Object.values(PRICES).includes(priceId)) {
    return { status: 400, body: { error: 'Invalid price ID' } };
  }

  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    payment_method_types: ['card'],
    line_items: [{ price: priceId, quantity: 1 }],
    customer_email: customerEmail || undefined,
    success_url: successUrl || 'soulo://payment/success',
    cancel_url: cancelUrl || 'soulo://payment/cancel',
    metadata: metadata || {},
    subscription_data: {
      metadata: metadata || {},
    },
  });

  return {
    status: 200,
    body: {
      sessionId: session.id,
      url: session.url,
      expiresAt: session.expires_at,
    },
  };
}

// GET /verify-session/:sessionId
async function verifySession(sessionId) {
  const session = await stripe.checkout.sessions.retrieve(sessionId, {
    expand: ['subscription'],
  });

  return {
    status: 200,
    body: {
      paid: session.payment_status === 'paid',
      plan: session.metadata?.plan || null,
      customerId: session.customer,
      subscriptionId: session.subscription?.id,
    },
  };
}

// POST /customer-portal
async function customerPortal(body) {
  const { customerId } = body;
  if (!customerId) {
    return { status: 400, body: { error: 'customerId required' } };
  }

  const session = await stripe.billingPortal.sessions.create({
    customer: customerId,
    return_url: 'soulo://settings',
  });

  return { status: 200, body: { url: session.url } };
}

// POST /webhook
async function handleWebhook(body, signature) {
  const event = stripe.webhooks.constructEvent(
    body,
    signature,
    process.env.STRIPE_WEBHOOK_SECRET
  );

  switch (event.type) {
    case 'checkout.session.completed': {
      const session = event.data.object;
      // Update user's subscription in local DB
      // Send push notification confirming subscription
      console.log(`Checkout completed: ${session.id} for ${session.customer_email}`);
      break;
    }
    case 'invoice.payment_succeeded': {
      const invoice = event.data.object;
      console.log(`Payment succeeded: ${invoice.id}`);
      break;
    }
    case 'customer.subscription.updated':
    case 'customer.subscription.deleted': {
      const subscription = event.data.object;
      console.log(`Subscription ${subscription.id} ${event.type}`);
      break;
    }
  }

  return { status: 200, body: { received: true } };
}

// 🌐 Main handler (Vercel-style)
module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, headers);
    res.end();
    return;
  }

  try {
    let result;

    if (req.url.startsWith('/create-checkout-session') && req.method === 'POST') {
      result = await createCheckoutSession(req.body);
    } else if (req.url.startsWith('/verify-session/') && req.method === 'GET') {
      const sessionId = req.url.split('/verify-session/')[1];
      result = await verifySession(sessionId);
    } else if (req.url.startsWith('/customer-portal') && req.method === 'POST') {
      result = await customerPortal(req.body);
    } else if (req.url.startsWith('/webhook') && req.method === 'POST') {
      const sig = req.headers['stripe-signature'];
      result = await handleWebhook(JSON.stringify(req.body), sig);
    } else {
      result = { status: 404, body: { error: 'Not found' } };
    }

    res.writeHead(result.status, { ...headers, 'Content-Type': 'application/json' });
    res.end(JSON.stringify(result.body));
  } catch (err) {
    console.error('Stripe handler error:', err);
    res.writeHead(500, { ...headers, 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
};
