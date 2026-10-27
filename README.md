# ENWAKE candle store

A complete candle storefront and owner dashboard in the burgundy, ivory and charcoal palette of your reference image. ENWAKE is a working brand name and can be changed in Store manager → Settings.

## What is included

- Responsive storefront; search, category and scent filters, price sorting and saved favourites.
- Product detail dialogs with scent notes, size, stock and candle care.
- Persistent shopping bag with a **directly editable number box**, plus/minus buttons, stock limits and recalculated totals.
- Guest checkout, Indian address validation, configurable shipping and percentage offer codes.
- Orders saved in a server database with item snapshots, idempotent retries and atomic stock reservation.
- Private tracking links and signed-in order history.
- Owner-only product and order management; image uploads, stock, prices, visibility and CSV export.
- Stock restored exactly once when an order is cancelled.
- Configurable brand, email, WhatsApp chat link, Instagram and policies.
- Newsletter subscription storage with consent.
- Razorpay order creation, signature verification, captured-payment check and signed webhook handling.

## Current state

This build starts in **preview mode**. Products, prices, burn times and generated product photographs are illustrative. Preview orders are stored but do not collect money or create shipments. Replace sample products, photos and policies before accepting real orders.

This is a separate React/TypeScript + Vinext application on Cloudflare Workers, with D1 for records and R2 for images. It does not reuse or modify the Thread in Loops Supabase database. It is **not a static Netlify Drop folder**; the API routes require a Worker server. Hosting with ChatGPT Sites provides ChatGPT sign-in. Google/Supabase sign-in is not implemented in this package.

WhatsApp opens a customer-initiated chat. Automatic WhatsApp and email notifications, courier booking, automatic refunds, tax invoices and automatic payment-expiry cancellation are not connected. Pending orders keep stock reserved until the owner cancels them. Refunds must be processed in the payment provider.

## Run locally

Requires Node.js 22.13 or newer (Node 24 recommended), pnpm, and Python 3 for the database test.

```bash
corepack enable
pnpm install --frozen-lockfile
cp .dev.vars.example .dev.vars
pnpm build
node scripts/migrate-local.mjs
pnpm dev
```

Open the URL printed by the development server (normally http://localhost:5173).

The first request loads the example catalogue once. Editing or hiding a sample product will not reinsert it. In local portable development, use the normal sign-in link; the supplied starter simulates an account with email `seedy@sites.test`. The example admin setting authorises that local account. The mock sign-in is not used on the hosted site.

`/admin` opens the store manager. Hosted admin access uses the `STORE_ADMIN_EMAILS` secret, checked on every admin API request. Never put secrets in frontend code or commit `.dev.vars`.

## Runtime configuration

| Variable | Purpose |
| --- | --- |
| STORE_ADMIN_EMAILS | Comma-separated authorised owner emails. Required for admin. |
| ORDER_MODE | `preview` by default; set `live` only after completing launch setup. |
| ENABLE_COD | Optional `true` to offer cash on delivery in live mode. |
| RAZORPAY_KEY_ID | Candle business Razorpay key ID. |
| RAZORPAY_KEY_SECRET | Matching server-only Razorpay secret. |
| RAZORPAY_WEBHOOK_SECRET | Independent secret for `/api/payments/webhook`. |

Configure runtime values through hosting settings. The hosting manifest declares logical `DB` and `BUCKET` bindings. D1 migrations are in `drizzle/` and are applied on deployment through ChatGPT Sites. The local migration script uses the generated Wrangler configuration after `pnpm build`.

## Before taking payments

1. Add actual candle photos and verified product descriptions; turn off “Sample product” on actual stock only.
2. Set support email, WhatsApp number including country code, shipping, return terms and any offer code.
3. Add the candle business's Razorpay test keys as runtime secrets and test payment capture, failed payment, webhook retries and order tracking.
4. Configure the webhook endpoint with the independent webhook secret and subscribe to `payment.captured` / `order.paid`. A private site blocks external provider callbacks; enable provider-reachable hosting before relying on webhooks.
5. Switch to matching Razorpay live keys after account activation, set `ORDER_MODE=live`, and redeploy. The delivered site stays private until you choose customer access.
6. Confirm admin access, a real-product test order, stock reservation/cancellation, and shipping policy before inviting customers.

Payment signatures and amount checks run server-side. Only captured, matching payments are recorded as received. Order cancellation restores stock but does not issue a refund.

Official Razorpay references: https://razorpay.com/docs/api/orders/create/ and https://razorpay.com/docs/payments/payment-gateway/web-integration/standard/integration-steps/

## Main files

- `app/storefront.tsx`: customer shopping flow and editable quantity component.
- `app/globals.css`: desktop and mobile theme.
- `app/admin/manager.tsx`: owner dashboard.
- `app/api/`: catalogue, checkout, admin, images, newsletter and payments.
- `app/lib/catalog.ts`: sample collection and quantity/pricing helpers.
- `app/lib/server.ts`: identity, authorisation, database and payment helpers.
- `db/schema.ts`: typed schema; `drizzle/`: SQL migration and inventory triggers.
- `public/images/`: bundled generated product imagery and your palette reference.

## Checks

```bash
pnpm exec tsc --noEmit
node scripts/check-domain.mjs
python3 scripts/check-stock.py
pnpm build
```

The payment code is included but has not been tested against a live Razorpay account. This source archive excludes dependencies, build output, local databases and secrets. Install the dependencies before running it.
