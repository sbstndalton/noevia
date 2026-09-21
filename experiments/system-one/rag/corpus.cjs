'use strict';
// Synthetic, seeded corpus for the RAG rerank prototype (docs/research/system-one/09 §9.2).
// Four document sets built to be hard for a bi-encoder: many near-identical records that differ
// only in the fact a question asks about (same vendor, other month; same service, other host).
// Every task carries its gold answer and the evidence string(s) that prove the right chunk was
// retrieved. Nothing here is real data.

function rng(seed) { let s = seed >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32); }
const pick = (r, list) => list[Math.floor(r() * list.length)];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

function finance(r) {
  const vendors = [
    { name: 'Northgate Hydro', kind: 'electricity', base: 90 },
    { name: 'Riverbend Water', kind: 'water and sewer', base: 45 },
    { name: 'Lakeshore Gas', kind: 'natural gas', base: 70 },
    { name: 'Copperline Internet', kind: 'internet', base: 85 },
  ];
  const records = [];
  let n = 4100;
  for (const year of [2019, 2020, 2021, 2022, 2023, 2024, 2025]) for (let m = 0; m < 12; m++) for (const v of vendors) {
    if (v.name === 'Copperline Internet' && year === 2023 && m < 6) continue; // absent: used by unanswerable tasks
    const amount = (v.base + r() * 60).toFixed(2);
    const inv = `INV-${v.name.slice(0, 2).toUpperCase()}-${n++}`;
    const due = `${MONTHS[(m + 1) % 12]} ${5 + Math.floor(r() * 20)}, ${m === 11 ? year + 1 : year}`;
    records.push({ vendor: v.name, kind: v.kind, year, month: MONTHS[m], amount, inv, due,
      text: `${v.name} (${v.kind}) invoice ${inv} for ${MONTHS[m]} ${year}: amount due $${amount}, payment due ${due}. Account 88-${1000 + Math.floor(r() * 9000)}. Paid by automatic withdrawal from the joint chequing account.` });
  }
  const doc = records.map((x) => x.text).join('\n\n');
  const tasks = [];
  for (let i = 0; i < 12; i++) {
    const x = pick(r, records);
    const ask = i % 3 === 0 ? `What was the invoice number of the ${x.vendor} bill for ${x.month} ${x.year}?` :
      i % 3 === 1 ? `How much was the ${x.kind} bill for ${x.month} ${x.year}?` : `When was the ${x.vendor} bill for ${x.month} ${x.year} due?`;
    tasks.push({ id: `fin-${i}`, family: 'needle', question: ask,
      gold: [i % 3 === 0 ? x.inv : i % 3 === 1 ? `$${x.amount}` : x.due], evidence: [x.inv] });
  }
  tasks.push({ id: 'fin-u1', family: 'unanswerable', question: 'How much was the Copperline Internet bill for March 2023?', gold: [], evidence: [] });
  tasks.push({ id: 'fin-u2', family: 'unanswerable', question: 'How much was the Northgate Hydro bill for March 2018?', gold: [], evidence: [] });
  return { name: 'Household bills 2019-2025.md', text: doc, tasks };
}

function homelab(r) {
  const services = ['Grafana', 'Prometheus', 'Home Assistant', 'Jellyfin', 'Paperless', 'Vaultwarden', 'Gitea', 'Immich'];
  const hosts = [];
  for (let h = 1; h <= 40; h++) {
    const name = `lab-${String(h).padStart(2, '0')}`;
    const svc = services[h % services.length];
    const vlan = 10 + ((h * 7) % 40);
    hosts.push({ name, svc, vlan, ip: `10.20.${vlan}.${10 + h}`, port: 3000 + Math.floor(r() * 6000), backup: `${pick(r, ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'])} at ${String(1 + Math.floor(r() * 5)).padStart(2, '0')}:30`, ram: pick(r, [8, 16, 32, 64]) });
  }
  const text = hosts.map((x) => `## Host ${x.name}\n\n${x.name} runs ${x.svc} on port ${x.port}. It sits on VLAN ${x.vlan} with the address ${x.ip} and has ${x.ram} GB of RAM. Nightly snapshots are replicated to the backup pool; the full backup runs every ${x.backup}. To restart ${x.svc} on ${x.name}, use the service manager and then check the health endpoint on port ${x.port}.`).join('\n\n');
  const tasks = [];
  for (let i = 0; i < 10; i++) {
    const x = hosts[(i * 5) % hosts.length];
    const [q, g] = i % 4 === 0 ? [`Which port does ${x.svc} use on ${x.name}?`, String(x.port)] :
      i % 4 === 1 ? [`What is the IP address of ${x.name}?`, x.ip] :
      i % 4 === 2 ? [`When does the full backup of ${x.name} run?`, x.backup] : [`Which VLAN is ${x.name} on?`, String(x.vlan)];
    tasks.push({ id: `lab-${i}`, family: 'project', question: q, gold: [g], evidence: [`## Host ${x.name}\n`] });
  }
  tasks.push({ id: 'lab-u1', family: 'unanswerable', question: 'What port does Nextcloud use on lab-41?', gold: [], evidence: [] });
  return { name: 'Homelab runbook.md', text, tasks };
}

function meetings(r) {
  const people = ['Priya', 'Marcus', 'Elena', 'Tomasz', 'Aiko', 'Dev', 'Hannah', 'Luis'];
  const topics = ['the storage migration', 'the budget review', 'the vendor shortlist', 'the onboarding guide', 'the security audit', 'the Q3 roadmap', 'the office move', 'the backup policy'];
  const notes = [];
  // Budget figures are unique per week (r() is still drawn, so every other record stays identical).
  for (let w = 1; w <= 60; w++) {
    const topic = topics[w % topics.length];
    notes.push({ w, topic, owner: pick(r, people), deadline: `${MONTHS[(w + 3) % 12]} ${1 + Math.floor(r() * 27)}`, code: `DEC-${200 + w}`, budget: w % 5 === 0 ? (r(), `cut to $${(10 + w) * 1000}`) : null });
  }
  const text = notes.map((x) => `### Week ${x.w} meeting notes\n\nDiscussed ${x.topic}. Decision ${x.code}: ${x.owner} owns the next step, due ${x.deadline}.${x.budget ? ` The project budget was ${x.budget}.` : ''} Everyone else to review the draft before the next meeting. Action items were copied to the tracker.`).join('\n\n');
  const tasks = [];
  for (let i = 0; i < 4; i++) {
    const x = notes[(i * 7 + 2) % notes.length];
    tasks.push({ id: `mtg-${i}`, family: 'needle', question: `Who owns decision ${x.code}, and when is it due?`, gold: [x.owner, x.deadline], evidence: [x.code + ':'] });
  }
  const cuts = notes.filter((x) => x.budget);
  for (let i = 0; i < 4; i++) {
    const x = cuts[i % cuts.length];
    tasks.push({ id: `mtg-m${i}`, family: 'multihop', question: `In the week the project budget was ${x.budget}, which topic was discussed and who owns the resulting decision?`, gold: [x.topic.replace(/^the /, ''), x.owner], evidence: [`### Week ${x.w} meeting notes`] });
  }
  tasks.push({ id: 'mtg-u1', family: 'unanswerable', question: 'Who owns decision DEC-999?', gold: [], evidence: [] });
  return { name: 'Team meeting notes.md', text, tasks };
}

function manual(r) {
  const parts = ['pump', 'heater', 'fan', 'valve', 'sensor', 'filter', 'display', 'battery'];
  const codes = [];
  for (let c = 1; c <= 120; c++) {
    const part = parts[c % parts.length];
    codes.push({ code: `E${String(c).padStart(2, '0')}`, part, fix: pick(r, ['reset the unit and wait 30 seconds', 'clean the intake grille', 'replace the fuse marked F2', 'check the water supply valve is fully open', 'recalibrate from the service menu', 'contact support with the serial number']), minutes: 5 + Math.floor(r() * 50) });
  }
  const text = codes.map((x) => `Error ${x.code} — ${x.part} fault. The controller reports a problem with the ${x.part}. First response: ${x.fix}. Typical repair time is ${x.minutes} minutes. If ${x.code} returns within 24 hours, log it and escalate.`).join('\n\n');
  const tasks = [];
  for (let i = 0; i < 8; i++) {
    const x = codes[(i * 9 + 3) % codes.length];
    tasks.push({ id: `man-${i}`, family: 'needle', question: i % 2 ? `What should I do first when the display shows ${x.code}?` : `Which part does error ${x.code} refer to, and how long does the repair usually take?`, gold: i % 2 ? [x.fix] : [x.part, `${x.minutes} minutes`], evidence: [`Error ${x.code} —`] });
  }
  tasks.push({ id: 'man-u1', family: 'unanswerable', question: 'What does error E177 mean?', gold: [], evidence: [] });
  tasks.push({ id: 'man-u2', family: 'unanswerable', question: 'What is the warranty period for the heater?', gold: [], evidence: [] });
  return { name: 'Appliance service manual.md', text, tasks };
}

function build(seed = 20260921) {
  const r = rng(seed);
  const files = [finance(r), homelab(r), meetings(r), manual(r)];
  const tasks = files.flatMap((f) => f.tasks);
  return { files: files.map(({ name, text }) => ({ name, content: text })), tasks };
}

module.exports = { build };
if (require.main === module) {
  const { files, tasks } = build();
  for (const f of files) console.log(f.name, f.content.length, 'chars');
  console.log(tasks.length, 'tasks', Object.entries(tasks.reduce((a, t) => ((a[t.family] = (a[t.family] || 0) + 1), a), {})));
}
