import sqlite3

con = sqlite3.connect("file:/app/data/index.db?mode=ro", uri=True)
cur = con.cursor()
tables = [r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'")]
print("tables:", tables)
for t in tables:
    n = cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
    print(f"  {t}: {n} rows")

for t in tables:
    if "journal" in t.lower() or "entry" in t.lower():
        cols = [c[1] for c in cur.execute(f"PRAGMA table_info({t})")]
        print(f"{t} columns:", cols)
        status_col = next((c for c in cols if c.lower() in ("status", "applied", "state")), None)
        for row in cur.execute(f"SELECT * FROM {t} ORDER BY rowid DESC LIMIT 6"):
            redacted = []
            for i, v in enumerate(row):
                s = str(v)
                # print only metadata-ish short fields, redact long prose fields
                if len(s) > 60:
                    redacted.append(f"<{len(s)} chars redacted>")
                else:
                    redacted.append(s)
            print("  recent:", redacted)
