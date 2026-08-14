# Polar setup

Production organization: [emilian-scheel](https://polar.sh/dashboard/emilian-scheel). This integration talks to the **live** Polar environment (`POLAR_SERVER=production`).

## Files created or changed

- `src/lib/polar.ts` — shared `@polar-sh/sdk` client (`POLAR_SERVER` selects sandbox vs production)
- `src/app/checkout/route.ts` — `GET /checkout?products=<id>` creates a session and 302s to Polar hosted checkout (no success URL; Polar shows its own confirmation)
- `src/app/api/webhook/polar/route.ts` — `POST` webhook; verifies `POLAR_WEBHOOK_SECRET`; TODO stubs for `order.paid` and `customer.state_changed`
- `src/app/page.tsx` — Buy button uses `NEXT_PUBLIC_POLAR_PRODUCT_ID` to hit `/checkout?products=<id>` (landing page otherwise unchanged)
- `package.json` / `bun.lock` — added `@polar-sh/sdk`

No customer portal route. Polar hosts the portal and emails customers a link after purchase.

## Env keys added (values never committed)

`.env` is gitignored. Keys:

- `POLAR_ACCESS_TOKEN`
- `POLAR_WEBHOOK_SECRET`
- `POLAR_SERVER`
- `NEXT_PUBLIC_POLAR_PRODUCT_ID`

Set the same keys on Vercel for `https://ports-on-mac.vercel.app` or checkout and webhooks will fail in production.

## Polar resources

| Resource | Id |
| --- | --- |
| Product (Ports on Mac, $10 one-time) | `66c8ee2f-990e-4d0d-b2f6-97e1ec5d4618` |
| Webhook endpoint | `8031d766-b947-4c9d-9658-c54a6252d56e` |
| Webhook URL | `https://ports-on-mac.vercel.app/api/webhook/polar` |

Existing product was reused; no new product was created.

## Verify before merging

1. Copy `POLAR_ACCESS_TOKEN`, `POLAR_WEBHOOK_SECRET`, and `POLAR_SERVER=production` into Vercel env, then deploy.
2. Local: `bun run dev` in `web/`, then open [http://localhost:3000/checkout?products=66c8ee2f-990e-4d0d-b2f6-97e1ec5d4618](http://localhost:3000/checkout?products=66c8ee2f-990e-4d0d-b2f6-97e1ec5d4618) (or click Buy). You should land on Polar hosted checkout.
3. This is production. A completed checkout charges **$10** unless you apply a 100% discount code on the Polar page. Creating `TEST100` via API returned 403 (token needs `discounts:write`). Create a 100% code in the [discounts dashboard](https://polar.sh/dashboard/emilian-scheel) if you want a no-charge test.
4. After deploy, Polar dashboard → Webhooks should show deliveries to `/api/webhook/polar`. Handlers are stubs until access-granting logic is added.
