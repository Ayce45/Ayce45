// Spotter for Technogym : relais Cloudflare (Pages "_worker.js" ou Worker).
//
// Sans etat : se connecte a Mywellness avec les identifiants configures (variables d'environnement /
// secrets du projet Cloudflare), lit la seance courante et renvoie a la montre un JSON de quelques Ko.
// Endpoints (les memes que le backend Python, sous-ensemble utilise par l'app montre) :
//   GET  /health            etat
//   GET  /live              seance courante Technogym (bornes, equipements, app), compactee
//   POST /live/hr           echantillons cardio de la montre (acceptes, non conserves sans stockage)
//   POST /live/mark         {"position": n} : marque un exercice fait dans la seance ouverte
//   POST /live/close        ferme la seance ouverte cote Technogym
//   GET  /                  page d'accueil (statique)
// Deux modes d'authentification :
//   * multi-utilisateur (store) : la montre envoie les identifiants Technogym saisis dans Garmin Connect,
//     en-tetes X-MW-Email et X-MW-Password ; le relais se connecte pour cet utilisateur, garde le jeton
//     Mywellness en memoire (jamais ecrit) et ne stocke aucun identifiant ;
//   * mono-utilisateur (beta perso) : identifiants dans les secrets du projet (MYWELLNESS_EMAIL,
//     MYWELLNESS_PASSWORD) et token d'appairage PAIR_TOKEN attendu dans X-Pair-Token ou ?token=.
// FACILITY_URL (optionnel) : salle a utiliser, sinon la premiere salle du compte.

const CORE = "https://core.mywellness.com";
const SERVICES = "https://services.mywellness.com";
const HEADERS = {
  "X-MWAPPS-APPID": "EC1D38D7-D359-48D0-A60C-D8C0B8FB9DF9",
  "X-MWAPPS-CLIENT": "enduserweb",
  "X-MWAPPS-CLIENTVERSION": "1.0,enduserweb",
  "Content-Type": "application/json",
  "Accept": "application/json",
};

// Jetons Mywellness gardes en memoire de l'isolat, par utilisateur (cle = empreinte des identifiants).
const sessions = new Map(); // key -> { token, userId, facilityUrl, at }
const liveCaches = new Map(); // key -> { at, body }
const prevCaches = new Map(); // key -> { at, map } : derniere execution et record par exercice
const PREV_TTL_MS = 10 * 60 * 1000;
const SESSION_TTL_MS = 6 * 3600 * 1000;
const LIVE_CACHE_MS = 8000;

async function credKey(creds) {
  const data = new TextEncoder().encode(`${creds.email}\u0000${creds.password}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Identifiants de la requete : ceux envoyes par la montre, sinon ceux du projet (mode perso).
function credentials(request, env) {
  const email = request.headers.get("X-MW-Email");
  const password = request.headers.get("X-MW-Password");
  if (email && password) return { email, password, source: "watch" };
  if (env.MYWELLNESS_EMAIL && env.MYWELLNESS_PASSWORD) return { email: env.MYWELLNESS_EMAIL, password: env.MYWELLNESS_PASSWORD, source: "env" };
  return null;
}

async function login(env, creds, key) {
  const cached = sessions.get(key);
  if (cached && Date.now() - cached.at < SESSION_TTL_MS) return cached;
  const r = await fetch(`${CORE}/v2/enduser/authentication/login`, {
    method: "POST",
    headers: HEADERS,
    body: JSON.stringify({ username: creds.email, password: creds.password, keepMeLoggedIn: true }),
  });
  if (!r.ok) throw new Error(`login HTTP ${r.status}`);
  const j = await r.json();
  const d = j.data || j;
  const token = d.token || d.accessToken || (d.credentials && d.credentials.token);
  const userId = d.userContext?.id || d.userId || d.id;
  const facilities = d.userContext?.facilities || d.facilities || [];
  const facilityUrl = env.FACILITY_URL || (facilities[0] && (facilities[0].url || facilities[0].facilityUrl));
  if (!token || !userId || !facilityUrl) {
    if (r.status === 200 && (j.errors || d.errors)) throw new Error("Identifiants Technogym refuses");
    throw new Error("login : reponse inattendue " + JSON.stringify(Object.keys(d)));
  }
  const s = { token, userId, facilityUrl, at: Date.now() };
  sessions.set(key, s);
  if (sessions.size > 500) sessions.delete(sessions.keys().next().value);
  return s;
}

async function action(env, ctx, name, body, retry = true) {
  const s = await login(env, ctx.creds, ctx.key);
  const r = await fetch(`${SERVICES}/${s.facilityUrl}/Training/User/${s.userId}/${name}`, {
    method: "POST",
    headers: { ...HEADERS, Authorization: `Bearer ${s.token}` },
    body: JSON.stringify(body || {}),
  });
  if (r.status === 401 && retry) { sessions.delete(ctx.key); return action(env, ctx, name, body, false); }
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
    const reps = v.IsoReps ?? v.Reps, weight = v.IsoWeight ?? v.Weight, dur = v.Duration, rest = v.RestTime ?? v.Rest;
    if (reps != null || weight != null || dur != null) {
      const s = {};
      if (reps != null) s.reps = Math.round(Number(reps));
      if (weight != null) s.weight_kg = Number(weight);
      if (dur != null) s.duration_s = Math.round(Number(dur));
      if (rest != null) s.rest_s = Math.round(Number(rest));
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

function rm1(refs) {
  for (const r of refs || []) if (r && String(r.name || "").toLowerCase() === "rm1" && r.value != null) return Math.round(Number(r.value) * 10) / 10;
  return undefined;
}

function ymd(d) { return d.toISOString().slice(0, 10).replace(/-/g, ""); }

// Derniere execution et record de charge par exercice, sur les 8 dernieres seances de 90 jours.
async function previousByExercise(env, ctx) {
  const c = prevCaches.get(ctx.key);
  if (c && Date.now() - c.at < PREV_TTL_MS) return c.map;
  const map = {};
  try {
    const end = new Date(); const start = new Date(end.getTime() - 90 * 86400000);
    const hist = await action(env, ctx, "ActivityHistory", { startDay: ymd(start), endDay: ymd(end), justThisType: "WorkoutSession" });
    const items = (hist.items || []).sort((a, b) => String(b.partitionDate).localeCompare(String(a.partitionDate))).slice(0, 8);
    for (const it of items) {
      let raw;
      try { raw = await action(env, ctx, "GetPerformedWorkoutSessionByIdCr", { idCr: Number(it.idCr), partitionDate: String(it.partitionDate) }); } catch (e) { continue; }
      const day = String(it.partitionDate); const dayIso = day.length === 8 ? `${day.slice(0, 4)}-${day.slice(4, 6)}-${day.slice(6, 8)}` : day;
      for (const act of raw.physicalActivities || []) {
        const sets = stepsToSets(((act.performedPhysicalActivity || {}).data || {}).steps);
        if (!sets.length) continue;
        const best = Math.max(...sets.map((s) => s.weight_kg || 0));
        for (const key of [String(act.physicalActivityId || ""), String(act.physicalActivityName || "")]) {
          if (!key) continue;
          if (!map[key]) map[key] = { last_sets: sets, last_on: dayIso, best };
          else map[key].best = Math.max(map[key].best, best);
        }
      }
    }
  } catch (e) { /* historique indisponible : on sert le direct sans "derniere fois" */ }
  prevCaches.set(ctx.key, { at: Date.now(), map });
  if (prevCaches.size > 500) prevCaches.delete(prevCaches.keys().next().value);
  return map;
}

export function compactLive(cur, prev) {
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
      muscle_types: (e.muscles || []).map((m) => m && m.muscleType).filter(Boolean).slice(0, 6),
      pa_id: String(e.physicalActivityId || ""),
      rm1_kg: rm1(e.currentReferenceValues),
      last_sets: [], last_on: "",
    };
    const p = prev && (prev[ex.pa_id] || prev[ex.name] || prev[ex.short_name]);
    if (p) { ex.last_sets = p.last_sets; ex.last_on = p.last_on; if (p.best) ex.best_weight_kg = p.best; }
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

// Autorise : identifiants Technogym fournis par la montre (ils valent authentification), ou en mode perso
// le token d'appairage du projet.
function authorized(request, env, creds) {
  if (creds && creds.source === "watch") return true;
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
        return json({ status: "ok", relay: "cloudflare", modes: ["watch-credentials", ...(env.MYWELLNESS_EMAIL && env.MYWELLNESS_PASSWORD && env.PAIR_TOKEN ? ["pair-token"] : [])], users_cached: sessions.size });
      }
      let ctx = null;
      if (path === "/live" || path === "/live/hr" || path === "/live/mark" || path === "/live/close" || path === "/auth/check") {
        const creds = credentials(request, env);
        if (!authorized(request, env, creds)) return json({ detail: "Identifiants Technogym (X-MW-Email, X-MW-Password) ou token d'appairage requis" }, 401);
        if (!creds) return json({ detail: "Identifiants Technogym absents" }, 401);
        ctx = { creds, key: await credKey(creds) };
      }
      if (path === "/auth/check" && request.method === "GET") {
        // verification des identifiants saisis dans Garmin Connect (login seul, rien d'autre)
        const s = await login(env, ctx.creds, ctx.key);
        return json({ ok: true, facility: s.facilityUrl });
      }
      if (path === "/live" && request.method === "GET") {
        const c = liveCaches.get(ctx.key);
        if (c && Date.now() - c.at < LIVE_CACHE_MS) return json(c.body);
        const cur = await action(env, ctx, "GetCurrentWorkoutSession", {});
        const prev = cur && cur.workoutSession ? await previousByExercise(env, ctx) : null;
        const body = compactLive(cur, prev);
        liveCaches.set(ctx.key, { at: Date.now(), body });
        if (liveCaches.size > 500) liveCaches.delete(liveCaches.keys().next().value);
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
        const cur = await action(env, ctx, "GetCurrentWorkoutSession", {});
        const ws = cur && cur.workoutSession;
        if (!ws) return json({ detail: "Aucune seance ouverte" }, 409);
        const partition = Number(String(ws.startedOn || "").slice(0, 10).replace(/-/g, "")) || Number(new Date().toISOString().slice(0, 10).replace(/-/g, ""));
        const res = await action(env, ctx, "MarkPhysicalActivityAsDone", { position: Number(b.position), userWorkoutSessionId: ws.workoutSessionId, idCr: ws.idCr, partitionDate: partition });
        liveCaches.delete(ctx.key);
        return json({ marked: true, response: res });
      }
      if (path === "/live/close" && request.method === "POST") {
        const cur = await action(env, ctx, "GetCurrentWorkoutSession", {});
        const ws = cur && cur.workoutSession;
        if (!ws) return json({ closed: false, reason: "Aucune seance ouverte" });
        const partition = Number(String(ws.startedOn || "").slice(0, 10).replace(/-/g, "")) || Number(new Date().toISOString().slice(0, 10).replace(/-/g, ""));
        const res = await action(env, ctx, "CloseWorkoutSession", { idCr: ws.idCr, partitionDate: String(partition) });
        liveCaches.delete(ctx.key);
        return json({ closed: true, response: res });
      }
      if (path === "/" && env.ASSETS) return env.ASSETS.fetch(request);
      if (path === "/") return new Response("Spotter for Technogym : relais en ligne. Voir /health.", { headers: { "Content-Type": "text/plain; charset=utf-8" } });
      return json({ detail: "Introuvable" }, 404);
    } catch (e) {
      const msg = String(e && e.message || e);
      return json({ detail: msg }, /refuses|login HTTP 4/.test(msg) ? 401 : 502);
    }
  },
};
