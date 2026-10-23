use serde::de::{self, Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use serde_json::{Map, Number, Value};
use std::fmt;
pub type Result<T> = std::result::Result<T, &'static str>;
struct Unique(Value);
impl<'de> Deserialize<'de> for Unique {
    fn deserialize<D: Deserializer<'de>>(d: D) -> std::result::Result<Self, D::Error> {
        struct V;
        impl<'de> Visitor<'de> for V {
            type Value = Unique;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("unique-key JSON")
            }
            fn visit_bool<E: de::Error>(self, x: bool) -> std::result::Result<Unique, E> {
                Ok(Unique(Value::Bool(x)))
            }
            fn visit_i64<E: de::Error>(self, x: i64) -> std::result::Result<Unique, E> {
                Ok(Unique(Value::Number(x.into())))
            }
            fn visit_u64<E: de::Error>(self, x: u64) -> std::result::Result<Unique, E> {
                Ok(Unique(Value::Number(x.into())))
            }
            fn visit_f64<E: de::Error>(self, x: f64) -> std::result::Result<Unique, E> {
                Number::from_f64(x)
                    .map(|n| Unique(Value::Number(n)))
                    .ok_or_else(|| E::custom("number"))
            }
            fn visit_str<E: de::Error>(self, x: &str) -> std::result::Result<Unique, E> {
                Ok(Unique(Value::String(x.into())))
            }
            fn visit_string<E: de::Error>(self, x: String) -> std::result::Result<Unique, E> {
                Ok(Unique(Value::String(x)))
            }
            fn visit_none<E: de::Error>(self) -> std::result::Result<Unique, E> {
                Ok(Unique(Value::Null))
            }
            fn visit_unit<E: de::Error>(self) -> std::result::Result<Unique, E> {
                self.visit_none()
            }
            fn visit_seq<A: SeqAccess<'de>>(
                self,
                mut a: A,
            ) -> std::result::Result<Unique, A::Error> {
                let mut out = Vec::new();
                while let Some(v) = a.next_element::<Unique>()? {
                    out.push(v.0);
                }
                Ok(Unique(Value::Array(out)))
            }
            fn visit_map<A: MapAccess<'de>>(
                self,
                mut a: A,
            ) -> std::result::Result<Unique, A::Error> {
                let mut out = Map::new();
                while let Some(k) = a.next_key::<String>()? {
                    if out.contains_key(&k) {
                        return Err(de::Error::custom("duplicate key"));
                    }
                    out.insert(k, a.next_value::<Unique>()?.0);
                }
                Ok(Unique(Value::Object(out)))
            }
        }
        d.deserialize_any(V)
    }
}
pub fn json(bytes: &[u8]) -> Result<Value> {
    let mut d = serde_json::Deserializer::from_slice(bytes);
    let v = Unique::deserialize(&mut d).map_err(|_| "json-invalid")?.0;
    d.end().map_err(|_| "json-trailing")?;
    Ok(v)
}
pub fn id(s: &str, account: bool) -> bool {
    s.len() == 36
        && s.bytes().all(|b| {
            b == b'-'
                || b.is_ascii_digit()
                || (b'a'..=b'f').contains(&b)
                || (account && (b'A'..=b'F').contains(&b))
        })
}
const TYPES: &[&str] = &[
    "job.created",
    "job.started",
    "step.started",
    "step.completed",
    "progress",
    "approval.requested",
    "approval.decided",
    "tool.started",
    "tool.completed",
    "tool.uncertain",
    "artifact.created",
    "checkpoint.created",
    "job.completed",
    "job.failed",
    "job.cancelled",
    "job.interrupted",
    "plan.proposed",
    "plan.edited",
    "plan.skipped",
    "assistant.output",
    "review.requested",
    "review.completed",
    "review.failed",
    "task.stage",
    "task.revision",
];
pub fn journal(bytes: &[u8], expected: &str) -> Result<String> {
    if bytes.len() > 8 * 1024 * 1024 {
        return Err("journal-cap");
    }
    let raw = std::str::from_utf8(bytes).map_err(|_| "utf8-invalid")?;
    let mut n = 0;
    let mut kind = None;
    let mut chained = None;
    for line in raw.split('\n').filter(|x| !x.is_empty()) {
        n += 1;
        if n > 65536 || line.len() > 256 * 1024 {
            return Err("events-cap");
        }
        let row = json(line.as_bytes())?;
        let obj = row.as_object().ok_or("event-shape")?;
        if row["job"].as_str() != Some(expected)
            || row["seq"].as_u64() != Some(n)
            || row["at"].as_u64().is_none_or(|x| x > 9_007_199_254_740_991)
            || !row["data"].is_object()
        {
            return Err("event-envelope");
        }
        let t = row["type"].as_str().ok_or("event-type")?;
        if !TYPES.contains(&t) {
            return Err("event-type");
        }
        if n == 1 {
            if t != "job.created" {
                return Err("creation-missing");
            }
            let k = row["data"]["kind"].as_str().ok_or("kind-invalid")?;
            if !["code", "deep_research"].contains(&k) {
                return Err("kind-unknown");
            }
            kind = Some(k.to_owned());
        } else if t == "job.created" {
            return Err("creation-duplicate");
        }
        let h = obj.contains_key("hash");
        if chained.is_some_and(|c| c != h) {
            return Err("chain-mixed");
        }
        chained = Some(h);
        if h {
            if row["hash"].as_str().is_none_or(|s| {
                s.len() != 64
                    || !s
                        .bytes()
                        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            }) || !obj.contains_key("previous")
            {
                return Err("chain-shape");
            }
        } else if obj.contains_key("previous") {
            return Err("chain-shape");
        }
    }
    kind.ok_or("journal-empty")
}
pub fn tuning(bytes: &[u8], calibration: bool) -> Result<bool> {
    let v = json(bytes)?;
    let o = v.as_object().ok_or("tuning-shape")?;
    for k in ["history", "settings"] {
        if let Some(x) = o.get(k) {
            if !x.is_object() {
                return Err("tuning-shape");
            }
        }
    }
    match o.get("job") {
        None if !calibration => Ok(false),
        Some(Value::Null) => Ok(false),
        Some(job) if job.is_object() => match job["status"].as_str() {
            Some("running") => Ok(true),
            Some("passed" | "failed" | "cancelled" | "interrupted") => Ok(false),
            _ => Err("tuning-status"),
        },
        _ => Err("tuning-shape"),
    }
}
pub fn outcome(bytes: &[u8], expected: &str, kind: &str) -> Result<bool> {
    let v = json(bytes)?;
    let o = v.as_object().ok_or("delegate-shape")?;
    if o.len() != 3 || v["id"].as_str() != Some(expected) || v["kind"].as_str() != Some(kind) {
        return Err("delegate-shape");
    }
    match v["status"].as_str() {
        Some("completed" | "failed" | "cancelled" | "interrupted") => Ok(false),
        Some("queued" | "running" | "waiting_approval") => Ok(true),
        _ => Err("delegate-status"),
    }
}
