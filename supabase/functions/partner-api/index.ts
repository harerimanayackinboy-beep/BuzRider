import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const VT = ["motorcycle", "car", "van", "truck"];
const OFFER_SECONDS = 60;

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
const err = (code: string, message: string, s = 400) => json({ error: { code, message } }, s);

async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function authPartner(req: Request) {
  const key = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!key) return null;
  const { data } = await db.from("partners").select("id,name")
    .eq("api_key_hash", await sha256(key)).eq("is_active", true).maybeSingle();
  return data;
}

const validPt = (p: any) =>
  p && typeof p.lat === "number" && typeof p.lng === "number" && Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180;
const wkt = (p: any) => `SRID=4326;POINT(${p.lng} ${p.lat})`;

// Straight-line distance x 1.3 road factor (replace with Google Maps routing later)
function distanceKm(a: any, b: any) {
  const R = 6371, r = (x: number) => (x * Math.PI) / 180;
  const h = Math.sin(r(b.lat - a.lat) / 2) ** 2 +
    Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(r(b.lng - a.lng) / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(h)) * 1.3 * 10) / 10;
}

async function computePrice(vehicle: string, km: number, weight: number) {
  const { data: r } = await db.from("pricing_rules").select("*")
    .eq("vehicle_type", vehicle).eq("is_active", true)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (!r) return null;
  const raw = Number(r.base_fee) + Number(r.per_km) * km + Number(r.per_kg) * weight;
  return { price: Math.round(Math.max(Number(r.min_fee), raw) * 100) / 100, currency: r.currency };
}

function checkRoute(b: any) {
  if (!validPt(b?.pickup) || !validPt(b?.destination)) return "pickup and destination need numeric lat and lng";
  if (!VT.includes(b?.vehicle_type)) return "vehicle_type must be motorcycle, car, van or truck";
  return null;
}

async function quote(b: any) {
  const bad = checkRoute(b);
  if (bad) return err("invalid_request", bad);
  const km = distanceKm(b.pickup, b.destination);
  const p = await computePric
