# ENWAKE — Supabase candle store

The candle website now uses **Supabase PostgreSQL, Supabase Auth and Supabase Storage**, with a Netlify deployment configuration. The burgundy/ivory design and typed quantity boxes with + / − controls are preserved.

## Supabase setup — do these in order

Use a **separate Supabase project for ENWAKE**. Do not run this setup in the existing Thread in Loops database: both applications use table names such as `products` and `orders`.

1. Create the candle-store project in Supabase.
2. Open **SQL Editor → New query**, paste the complete contents of [`supabase/setup.sql`](supabase/setup.sql), and run it **once**. This creates the five tables, access policies, stock/payment functions, default store settings and `product-images` bucket.
3. In **Authentication → Users**, add your owner account with email and password. This app does not expose public email/password registration; you can keep new-user signups disabled when using guest checkout and owner-only login.
4. Run the following in SQL Editor, replacing the example email with the owner account you created:

   ```sql
   insert into public.admin_members(user_id)
   select id from auth.users where lower(email)=lower('your-admin-email@example.com')
   on conflict(user_id) do nothing;
   ```

5. Verify membership:

   ```sql
   select u.email from public.admin_members a
   join auth.users u on u.id=a.user_id;
   ```

6. Add these environment variables to **your ENWAKE Netlify site**, including the Functions scope:

   ```text
   SUPABASE_URL=https://YOUR-PROJECT.supabase.co
   SUPABASE_PUBLISHABLE_KEY=YOUR-PUBLISHABLE-KEY
   SUPABASE_SERVICE_ROLE_KEY=YOUR-SERVER-ONLY-SERVICE-ROLE-KEY
   ORDER_MODE=preview
   ENABLE_COD=false
   ENABLE_GOOGLE_LOGIN=false
   ```

   A legacy public `SUPABASE_ANON_KEY` can be used instead of `SUPABASE_PUBLISHABLE_KEY`. The service-role key is required by the server functions and must stay in hosting environment settings. Never put it in a public config file, a `VITE_` variable, browser code, GitHub or chat.

7. Deploy the GitHub repository through Netlify. Open `/admin` and sign in with the Supabase email/password account you created.
8. Add actual products using the admin dashboard. Set visibility, stock, scent notes, price and your uploaded photos. Configure store contact details, shipping, offer code and policies in Settings.
9. If you want sample products for testing, run [`supabase/seed-demo.sql`](supabase/seed-demo.sql) separately. They stay marked as samples and cannot be bought in live mode. The normal setup starts with an empty catalogue.

`supabase/migrations/202610280001_enwake.sql` is the same initial schema as `supabase/setup.sql`, for Supabase CLI users. **Run one route, not both.** Do not rerun the initial migration on an already configured database. Future database changes should use new migrations.

## Tables

| Table | Purpose |
|---|---|
| `products` | Candle information, image URLs, price in integer paise, stock and visibility |
| `orders` | Private customer data, item snapshots, totals, payment and delivery status |
| `admin_members` | Supabase Auth user IDs allowed to manage the store |
| `settings` | Store branding, support details, shipping, discount and policies |
| `subscribers` | Consenting newsletter subscribers |

Ordered items are saved as JSON snapshots inside `orders.items`; a separate `order_items` table is not required by this version. Images use the public `product-images` bucket. Uploaded images are public; customer addresses and orders are not.

## Deploy on Netlify

Import `enwakeofficial-ai/Enwake`, select branch `main`, and use the included `netlify.toml`:

- Build: `pnpm run build:netlify`
- Publish directory: `dist/netlify`
- Functions directory: `netlify/functions`
- Node: 24

The `/api/*` server function validates Supabase sessions and checks `admin_members` on every owner request. A browser does not gain admin rights merely by signing in. Product and image writes require verified membership. Checkout, payment verification and order reads go through server functions, keeping the service-role key out of frontend assets.

Do not deploy only the static folder using Netlify Drop: this version needs its server functions as well. Importing the GitHub repository deploys both. The frontend, Supabase project and Netlify site are separate resources.

## Sign-in

- Store owner: Supabase email/password on `/admin`.
- Customer: guest checkout works without an account. Existing Supabase accounts can sign in to see their own orders.
- Optional Google login: enable Google in Supabase Authentication → Providers, configure its credentials and allowed redirect URLs, add the deployed site origin/path to Supabase URL Configuration, then set `ENABLE_GOOGLE_LOGIN=true` in the host. It is off by default.
- Google users only get admin access if their Auth user ID is explicitly present in `admin_members`.

The internal ChatGPT Sites preview may still have a platform sign-in gate because it remains private. That gate is separate from store authentication. The Netlify build uses Supabase sign-in and has no ChatGPT login dependency.

## Payments and launch

Preview checkout saves test orders to Supabase, reserves stock and takes no payment. Use invented customer data for tests. Cancel test orders in admin to restore stock once.

For Razorpay, add server-only runtime values:

```text
RAZORPAY_KEY_ID=...
RAZORPAY_KEY_SECRET=...
RAZORPAY_WEBHOOK_SECRET=...
```

Configure `https://YOUR-NETLIFY-DOMAIN/api/payments/webhook` for `payment.captured` / `order.paid`. Test signatures, captured status, failed/retried payments and cancellation before using live keys. Then set `ORDER_MODE=live` and redeploy. Only actual products with “Sample product” unchecked can be purchased. Store email and WhatsApp contact must be filled in. Optional cash on delivery requires `ENABLE_COD=true`.

Orders calculate prices/shipping/discounts inside PostgreSQL. Product rows lock in stable ID order; duplicate retries use a transaction-level advisory lock. Stock changes roll back on rejected checkout. Cancellation restores stock exactly once. Captured payments are checked for order, amount and currency; cancelled paid orders are marked “Refund required.” Refunds must be handled in Razorpay separately.

Unpaid orders reserve stock until the owner cancels them. There is no automated payment-expiry cancellation. Automatic email/WhatsApp delivery and courier booking are not configured; WhatsApp opens a customer-initiated chat. Newsletter signup stores consented emails; an email campaign service is not connected.

## Local development

```bash
corepack enable
pnpm install --frozen-lockfile
cp .dev.vars.example .dev.vars
# Fill .dev.vars with your Supabase project settings; never commit it.
pnpm dev
```

For Netlify's local runtime, use `netlify dev` with the same server environment variables. Do not reuse the Thread in Loops project credentials unless you deliberately design a shared schema; this code assumes a dedicated candle-store project.

## Checks

```bash
pnpm exec tsc --noEmit
node scripts/check-domain.mjs
node scripts/check-supabase.mjs
node scripts/check-api.mjs
pnpm run build:netlify
pnpm build
```

The PostgreSQL migration is executed against an isolated embedded PostgreSQL engine with minimal stand-in Supabase Auth/Storage schemas. Tests cover permissions, price tampering, stock limits, retry idempotency, cancellation and payment transitions. They do not create or modify any live Supabase project. A live Supabase connection and Razorpay payment still require the owner's project configuration and live verification.

## Source map

- `app/storefront.tsx`: shopping UI, quantity controls and checkout.
- `app/admin/manager.tsx`: product, order and settings dashboard.
- `app/auth-form.tsx` / `app/lib/supabase-browser.ts`: Supabase login and session management.
- `server/store.ts`: shared Supabase-backed API, used by Netlify and the existing preview host.
- `netlify/functions/api.ts`: Netlify server adapter.
- `supabase/setup.sql`: complete initial database setup.
- `supabase/seed-demo.sql`: optional illustrative catalogue.

Reference documentation: [Supabase Auth](https://supabase.com/docs/reference/javascript/auth-signinwithpassword), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [database functions](https://supabase.com/docs/guides/database/functions), [Netlify routing](https://docs.netlify.com/build/functions/configuration/).
