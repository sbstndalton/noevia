/* Diary Companion UI — JSON API client, no build step. */
"use strict";

const $ = (sel) => document.querySelector(sel);
const chatlog = $("#chatlog");
const form = $("#chatform");
const input = $("#message");
const sendBtn = $("#sendbtn");
const logstatus = $("#logstatus");

let sessionCounter = 0; // index of the last exchange (for re-log)

function esc(s) {
  const d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function addMsg(role, text) {
  const el = document.createElement("div");
  el.className = `msg ${role}`;
  el.textContent = text;
  chatlog.appendChild(el);
  chatlog.scrollTop = chatlog.scrollHeight;
  return el;
}

function addStatus(decision, reason, index) {
  const el = document.createElement("div");
  el.className = "status";
  el.dataset.index = String(index);
  const tags = {
    logged: '<span class="tag logged">✓ logged</span>',
    skipped: '<span class="tag skipped">⊘ skipped</span>',
    error: '<span class="tag error">⚠ log error</span>',
  };
  el.innerHTML =
    (tags[decision] || tags.error) +
    (reason && decision === "error" ? ` ${esc(reason)}` : "") +
    (decision === "skipped" ? ' <button class="relog">log anyway</button>' : "") +
    (decision === "error" ? ' <button class="relog">retry</button>' : "");
  const btn = el.querySelector("button.relog");
  if (btn) {
    btn.addEventListener("click", async () => {
      btn.disabled = true;
      btn.textContent = "…";
      try {
        const res = await fetch("/api/relog", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ index, session_id: "default" }),
        });
        const data = await res.json();
        el.outerHTML = statusHTML(data.decision, data.reason || "", index);
      } catch (e) {
        btn.textContent = "retry failed";
      }
    });
  }
  chatlog.appendChild(el);
  return el;
}


form.addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  input.value = "";
  sendBtn.disabled = true;
  logstatus.textContent = "thinking…";
  addMsg("user", text);
  try {
    const res = await fetch("/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: text, session_id: "default" }),
    });
    const data = await res.json();
    if (!res.ok) {
      addMsg("error", data.error || "request failed");
      return;
    }
    addMsg("companion", data.reply);
    sessionCounter += 1;
    addStatus(data.decision, data.reason, sessionCounter - 1);
    logstatus.textContent = "";
    refreshSidebar();
  } catch (e) {
    addMsg("error", "network error: " + e.message);
  } finally {
    sendBtn.disabled = false;
    input.focus();
  }
});

async function refreshSidebar() {
  try {
    const [dayRes, healthRes] = await Promise.all([
      fetch("/api/day").then((r) => r.json()),
      fetch("/api/health").then((r) => r.json()),
    ]);
    $("#todaylog").textContent = dayRes.today_log || "(nothing logged yet today)";
    $("#standing").textContent = dayRes.standing || "(no standing sections yet)";
    $("#health").textContent =
      `model: ${healthRes.model}\njournal pending: ${healthRes.journal_pending}\nchunks indexed: ${healthRes.retrieval.chunks}\nvec available: ${healthRes.retrieval.vec_available}`;
  } catch (e) {
    $("#health").textContent = "sidebar refresh failed: " + e.message;
  }
}

refreshSidebar();
