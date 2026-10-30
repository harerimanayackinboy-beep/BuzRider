# BuzRider
MOVE. DELIVER. EARN. — Powered by BuzWork

Delivery & logistics platform. Independent Supabase backend, connected to BuzWork through a secure partner API.

- `supabase/migrations` — database schema + RLS (apply in order)
- `supabase/seed.sql` — starter pricing (ZAR)
- `supabase/functions/partner-api` — BuzWork-facing API (quotes, create delivery, get delivery)
- `docs/buzrider-buzwork-api.yaml` — API spec

## Secrets
Never commit API keys, service_role keys or passwords. Keep them in Supabase secrets / BuzWork server env.
