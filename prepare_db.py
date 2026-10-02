import json, os, re, html, sqlite3

SRC = "kbbi.json"
OUT = os.path.join("assets", "kbbi.db")

with open(SRC, encoding="utf-8-sig") as f:
    data = json.load(f)
items = data["dictionary"]
print("Items found:", len(items))

POS = {"n":"n","v":"v","a":"adj","adj":"adj","adv":"adv","pron":"pron",
       "num":"num","p":"p","conj":"conj","i":"i","prt":"prt","uk":"uk",
       "cak":"cak","ark":"ark","ki":"ki","lay":"lay","kas":"kas",
       "klas":"klas","lit":"lit","akr":"akr","nomina":"n","verba":"v",
       "adjektiva":"adj","adverbia":"adv","pronomina":"pron",
       "numeralia":"num","preposisi":"p","konjungsi":"conj",
       "interjeksi":"i","partikel":"prt"}

def pos_code(raw):
    if not raw:
        return ""
    out = []
    for part in re.split(r"[,;/\s]+", str(raw).lower().strip()):
        c = POS.get(part)
        if c and c not in out:
            out.append(c)
    return ",".join(out[:3])

def pos_from_html(raw):
    if not raw:
        return ""
    m = re.search(r"<i>\s*([a-z]+)\s*</i>", html.unescape(raw)[:100])
    return POS.get(m.group(1), "") if m else ""

def clean_text(raw):
    s = html.unescape(str(raw))
    s = re.sub(r"<[^>]+>", " ", s)
    return re.sub(r"\s+", " ", s).strip()

def clean_word(w):
    w = re.sub(r"\s+", " ", html.unescape(str(w)).lower()).strip()
    w = re.sub(r"\s*\(\d+\)\s*$", "", w)
    return w.strip()

os.makedirs("assets", exist_ok=True)
if os.path.exists(OUT):
    os.remove(OUT)
con = sqlite3.connect(OUT)
cur = con.cursor()
cur.executescript("""
CREATE TABLE entries(id INTEGER PRIMARY KEY, word TEXT NOT NULL,
  norm TEXT NOT NULL, pos TEXT, definition TEXT, len INTEGER NOT NULL);
CREATE TABLE compounds(id INTEGER PRIMARY KEY, first_token TEXT NOT NULL,
  phrase TEXT NOT NULL, tail TEXT NOT NULL, pos TEXT, len INTEGER NOT NULL);
CREATE UNIQUE INDEX idx_norm ON entries(norm);
CREATE INDEX idx_prefix ON entries(norm);
CREATE UNIQUE INDEX idx_phrase ON compounds(phrase);
CREATE INDEX idx_cprefix ON compounds(first_token);
""")

merged, order = {}, []
for it in items:
    w = clean_word(it.get("word", ""))
    raw = it.get("arti") or ""
    d = clean_text(raw)
    p = pos_code(it.get("type")) or pos_from_html(raw)
    if not w or len(w) > 40:
        continue
    e = merged.get(w)
    if e is None:
        merged[w] = [p, d]
        order.append(w)
    else:
        if d and d not in e[1]:
            e[1] = (e[1] + "; " + d).strip("; ")
        if not e[0] and p:
            e[0] = p

E, C = [], []
for w in order:
    p, d = merged[w]
    L = len(w.replace(" ", ""))
    E.append((w, w, p, d, L))
    if " " in w:
        f, t = w.split(" ", 1)
        C.append((f, w, t, p, L))

cur.executemany(
    "INSERT OR IGNORE INTO entries(word,norm,pos,definition,len) VALUES(?,?,?,?,?)", E)
cur.executemany(
    "INSERT OR IGNORE INTO compounds(first_token,phrase,tail,pos,len) VALUES(?,?,?,?,?)", C)
con.commit()

n = cur.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
m = cur.execute("SELECT COUNT(*) FROM compounds").fetchone()[0]
print(f"entries:   {n}")
print(f"compounds: {m}")
print(f"size: {os.path.getsize(OUT)/1e6:.1f} MB")
for w in ("meja", "rumah", "air mata", "meja tulis"):
    row = cur.execute(
        "SELECT word, pos, substr(definition,1,70) FROM entries WHERE norm=?",
        (w,)).fetchone()
    print("sample:", row)
con.close()
print("DONE - assets/kbbi.db is ready")
