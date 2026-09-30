// Spotter for Technogym : relais Cloudflare (Pages "_worker.js" ou Worker).
//
// Sans etat : se connecte a Mywellness avec les identifiants configures (variables d'environnement /
// secrets du projet Cloudflare), lit la seance courante et renvoie a la montre un JSON de quelques Ko.
// Endpoints (les memes que le backend Python, sous-ensemble utilise par l'app montre) :
//   GET  /health            etat
//   GET  /live              seance courante Technogym (bornes, equipements, app), compactee
//   POST /live/hr           echantillons cardio de la montre (acceptes, non conserves sans stockage)
//   POST /live/mark         {"position": n} : marque un exercice fait dans la seance ouverte
//   GET  /                  page d'accueil (statique)
// Variables : MYWELLNESS_EMAIL, MYWELLNESS_PASSWORD (secrets), PAIR_TOKEN (secret, attendu dans
// X-Pair-Token ou ?token=), FACILITY_URL (optionnel : sinon la premiere salle du compte).

const CORE = "https://core.mywellness.com";
const SERVICES = "https://services.mywellness.com";
const HEADERS = {
  "X-MWAPPS-APPID": "EC1D38D7-D359-48D0-A60C-D8C0B8FB9DF9",
  "X-MWAPPS-CLIENT": "enduserweb",
  "X-MWAPPS-CLIENTVERSION": "1.0,enduserweb",
  "Content-Type": "application/json",
  "Accept": "application/json",
};

// Jeton Mywellness garde en memoire de l'isolat (quelques minutes a quelques heures selon Cloudflare).
let session = null; // { token, userId, facilityUrl, at }
const SESSION_TTL_MS = 6 * 3600 * 1000;
const LIVE_CACHE_MS = 8000;
let liveCache = null; // { at, body }

async function login(env) {
  if (session && Date.now() - session.at < SESSION_TTL_MS) return session;
  const r = await fetch(`${CORE}/v2/enduser/authentication/login`, {
    method: "POST",
    headers: HEADERS,
    body: JSON.stringify({ username: env.MYWELLNESS_EMAIL, password: env.MYWELLNESS_PASSWORD, keepMeLoggedIn: true }),
  });
  if (!r.ok) throw new Error(`login HTTP ${r.status}`);
  const j = await r.json();
  const d = j.data || j;
  const token = d.token || d.accessToken || (d.credentials && d.credentials.token);
  const userId = d.userContext?.id || d.userId || d.id;
  const facilities = d.userContext?.facilities || d.facilities || [];
  const facilityUrl = env.FACILITY_URL || (facilities[0] && (facilities[0].url || facilities[0].facilityUrl));
  if (!token || !userId || !facilityUrl) throw new Error("login : reponse inattendue " + JSON.stringify(Object.keys(d)));
  session = { token, userId, facilityUrl, at: Date.now() };
  return session;
}

async function action(env, name, body, retry = true) {
  const s = await login(env);
  const r = await fetch(`${SERVICES}/${s.facilityUrl}/Training/User/${s.userId}/${name}`, {
    method: "POST",
    headers: { ...HEADERS, Authorization: `Bearer ${s.token}` },
    body: JSON.stringify(body || {}),
  });
  if (r.status === 401 && retry) { session = null; return action(env, name, body, false); }
  if (!r.ok) throw new Error(`${name} HTTP ${r.status}`);
  const j = await r.json();
  if (j.errors && j.errors.length) throw new Error(`${name} : ${j.errors.map((e) => e.message || e).join(", ")}`);
  return j.data !== undefined ? j.data : j;
}

// --- compaction de GetCurrentWorkoutSession (meme forme que app/mywellness/live.py)
function num(v) { const n = Number(v); return Number.isFinite(n) ? n : null; }

function stepsToSets(steps) {
  const out = [];
  for (const st of steps || []) {
    const props = st.properties || st.data || st.stepData || [];
    const v = {};
    for (const p of props) v[p.physicalProperty || p.name] = p.value;
    const reps = v.IsoReps ?? v.Reps, weight = v.IsoWeight ?? v.Weight, dur = v.Duration;
    if (reps != null || weight != null || dur != null) {
      const s = {};
      if (reps != null) s.reps = Math.round(Number(reps));
      if (weight != null) s.weight_kg = Number(weight);
      if (dur != null) s.duration_s = Math.round(Number(dur));
      out.push(s);
    }
  }
  return out;
}

function kind(type, isCardio) {
  const t = (type || "").toLowerCase();
  if (isCardio || t.startsWith("cardio")) return "cardio";
  if (t.startsWith("stretch")) return "stretching";
  return "strength";
}

export function compactLive(cur) {
  const ws = cur && cur.workoutSession;
  const st = { workout_id: "", date: new Date().toISOString().slice(0, 10), name: "", program_name: "", hr_samples: 0,
    has_current_workout: false, session_found: false, started_on: "", closed: false, done_count: 0, total_count: 0,
    exercises: [], fetched_at: Math.floor(Date.now() / 1000) };
  if (!ws || !ws.exercises || !ws.exercises.length) return st;
  st.workout_id = String(ws.workoutSessionId || "");
  st.has_current_workout = true;
  st.session_found = true;
  st.id_cr = num(ws.idCr) || undefined;
  st.started_on = String(ws.startedOn || "");
  st.name = String(ws.name || "");
  st.program_name = String((ws.extData || {}).mwc_workout_name || "");
  for (const e of ws.exercises) {
    const raw = String(e.executionStatus || "");
    const status = ["Done", "DoneAsModified"].includes(raw) ? "done" : raw === "Doing" ? "doing" : ["Partial", "PartiallyDone"].includes(raw) ? "partial" : "todo";
    let doneOn = String(e.doneOn || ""); if (doneOn.startsWith("0001-")) doneOn = "";
    const targets = stepsToSets(e.steps);
    const device = String(e.equipmentConnectedDevice || "");
    const ex = {
      position: num(e.position) || 0,
      name: String(e.name || e.shortName || ""),
      short_name: String(e.shortName || e.name || ""),
      equipment: String(e.equipmentName || ""),
      kind: kind(e.physicalActivityType, !!e.isCardio),
      status,
      source: device === "FullConnected" ? "machine" : status === "done" ? "manual" : "",
      device,
      done_on: doneOn,
      sets: status === "done" ? targets : [],
      target_sets: targets,
      picture_url: String(e.pictureUrl || (Array.isArray(e.imageFrames) && e.imageFrames[0]) || ""),
      equipment_picture_url: String(e.equipmentPictureUrl || ""),
      muscles: (e.muscles || []).map((m) => m && m.muscleName).filter(Boolean).slice(0, 4),
    };
    const mv = num(e.doneMove), kc = num(e.doneCalories);
    if (mv) ex.done_move = Math.round(mv);
    if (kc) ex.done_calories = Math.round(kc);
    st.exercises.push(ex);
  }
  st.exercises.sort((a, b) => a.position - b.position);
  st.total_count = st.exercises.length;
  st.done_count = st.exercises.filter((x) => x.status === "done").length;
  const doing = st.exercises.find((x) => x.status === "doing");
  const next = st.exercises.find((x) => x.status !== "done");
  st.current_position = doing ? doing.position : next ? next.position : undefined;
  return st;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } });
}

function authorized(request, env) {
  if (!env.PAIR_TOKEN) return false;
  const url = new URL(request.url);
  const t = request.headers.get("X-Pair-Token") || url.searchParams.get("token");
  return t === env.PAIR_TOKEN;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    try {
      if (path === "/health") {
        return json({ status: "ok", relay: "cloudflare", mywellness_configured: !!(env.MYWELLNESS_EMAIL && env.MYWELLNESS_PASSWORD), pair_token_configured: !!env.PAIR_TOKEN });
      }
      if (path === "/live" || path === "/live/hr" || path === "/live/mark") {
        if (!authorized(request, env)) return json({ detail: "Token d'appairage requis" }, 401);
        if (!env.MYWELLNESS_EMAIL || !env.MYWELLNESS_PASSWORD) return json({ detail: "Identifiants Technogym non configures (MYWELLNESS_EMAIL / MYWELLNESS_PASSWORD)" }, 503);
      }
      if (path === "/live" && request.method === "GET") {
        if (liveCache && Date.now() - liveCache.at < LIVE_CACHE_MS) return json(liveCache.body);
        const cur = await action(env, "GetCurrentWorkoutSession", {});
        const body = compactLive(cur);
        liveCache = { at: Date.now(), body };
        return json(body);
      }
      if (path === "/live/hr" && request.method === "POST") {
        const b = await request.json().catch(() => ({}));
        const n = Array.isArray(b.samples) ? b.samples.length : 0;
        // Sans stockage : on accuse reception. Avec un KV lie (env.HR), on pourrait les conserver ici.
        return json({ stored: n, workout_id: b.workout_id || "", total: n, persisted: false });
      }
      if (path === "/live/mark" && request.method === "POST") {
        const b = await request.json().catch(() => ({}));
        const cur = await action(env, "GetCurrentWorkoutSession", {});
        const ws = cur && cur.workoutSession;
        if (!ws) return json({ detail: "Aucune seance ouverte" }, 409);
        const partition = Number(String(ws.startedOn || "").slice(0, 10).replace(/-/g, "")) || Number(new Date().toISOString().slice(0, 10).replace(/-/g, ""));
        const res = await action(env, "MarkPhysicalActivityAsDone", { position: Number(b.position), userWorkoutSessionId: ws.workoutSessionId, idCr: ws.idCr, partitionDate: partition });
        liveCache = null;
        return json({ marked: true, response: res });
      }
      if (path === "/" && env.ASSETS) return env.ASSETS.fetch(request);
      if (path === "/") return new Response("Spotter for Technogym : relais en ligne. Voir /health.", { headers: { "Content-Type": "text/plain; charset=utf-8" } });
      return json({ detail: "Introuvable" }, 404);
    } catch (e) {
      return json({ detail: String(e && e.message || e) }, 502);
    }
  },
};
