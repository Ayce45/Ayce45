import fs from "node:fs";
import mod, { compactLive } from "./_worker.js";
const lines = fs.readFileSync("../scratch/poc_live_log.jsonl", "utf8").split("\n").filter(Boolean);
let checked = 0, maxBytes = 0;
for (const line of lines) {
  const r = JSON.parse(line);
  const c = compactLive(r.current);
  const b = JSON.stringify(c);
  maxBytes = Math.max(maxBytes, b.length);
  if (c.has_current_workout) { checked++; if (checked === 1) console.log("premiere capture :", c.name, c.done_count + "/" + c.total_count, "pos", c.current_position, c.exercises[1]); }
}
console.log("captures :", lines.length, "avec seance :", checked, "| plus grosse reponse compactee :", maxBytes, "octets");
const env = {};
const h = await mod.fetch(new Request("https://x/health"), env); console.log("health", h.status, await h.text());
const u = await mod.fetch(new Request("https://x/live"), { PAIR_TOKEN: "abc" }); console.log("live sans token ni identifiants", u.status);
const v = await mod.fetch(new Request("https://x/live", { headers: { "X-MW-Email": "a@b", "X-MW-Password": "x" } }), {}); console.log("live avec identifiants montre (login reel echoue ici) ->", v.status, (await v.text()).slice(0, 80));
const p = await mod.fetch(new Request("https://x/live/hr?token=abc", { method: "POST", body: JSON.stringify({ samples: [[1, 120], [2, 121]] }) }), { PAIR_TOKEN: "abc", MYWELLNESS_EMAIL: "a", MYWELLNESS_PASSWORD: "b" }); console.log("hr", p.status, await p.text());
