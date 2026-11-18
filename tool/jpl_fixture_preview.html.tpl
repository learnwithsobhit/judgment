<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Judgement Premier League — Season 1</title>
  <meta name="description" content="Official all-play-all fixture for Judgement Premier League Season 1. 14 players, 6 matchdays, every pair at the table." />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,700&family=Manrope:wght@400;500;600;700&display=swap" rel="stylesheet" />
  <style>
    :root {
      --felt: #0f3d2e;
      --felt-deep: #0a2a20;
      --felt-mid: #164a38;
      --gold: #d4a84b;
      --gold-soft: #e8c878;
      --ink: #f4efe4;
      --muted: rgba(244, 239, 228, 0.68);
      --line: rgba(212, 168, 75, 0.28);
      --chip: rgba(255, 255, 255, 0.06);
      --orange: #c45c26;
      --blue: #2a6f97;
      --six: #d4a84b;
      --hl: #ffe08a;
      --radius: 18px;
      --shadow: 0 18px 50px rgba(0, 0, 0, 0.35);
      font-synthesis: none;
    }

    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      color: var(--ink);
      font-family: "Manrope", system-ui, sans-serif;
      background:
        radial-gradient(1200px 600px at 10% -10%, rgba(212, 168, 75, 0.18), transparent 55%),
        radial-gradient(900px 500px at 100% 0%, rgba(42, 111, 151, 0.18), transparent 50%),
        linear-gradient(165deg, var(--felt-deep), var(--felt) 42%, #123d30 100%);
      min-height: 100vh;
    }

    body::before {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
      opacity: 0.07;
      background-image: url("data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fill-rule='evenodd'%3E%3Cg fill='%23ffffff' fill-opacity='1'%3E%3Cpath d='M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E");
      z-index: 0;
    }

    .wrap {
      position: relative;
      z-index: 1;
      width: min(1080px, calc(100% - 2rem));
      margin: 0 auto;
      padding: 1.25rem 0 4rem;
    }

    .hero {
      padding: 2.4rem 0 1.6rem;
      text-align: center;
      animation: rise 0.7s ease both;
    }

    .brand {
      font-family: "Fraunces", Georgia, serif;
      font-size: clamp(2.6rem, 8vw, 4.4rem);
      font-weight: 700;
      letter-spacing: -0.03em;
      line-height: 0.95;
      margin: 0;
      color: var(--ink);
    }

    .brand span {
      display: block;
      color: var(--gold-soft);
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      margin: 0 0 1rem;
      padding: 0.35rem 0.8rem;
      border: 1px solid var(--line);
      border-radius: 999px;
      color: var(--gold-soft);
      font-size: 0.78rem;
      font-weight: 600;
      letter-spacing: 0.12em;
      text-transform: uppercase;
    }

    .lede {
      max-width: 36rem;
      margin: 1rem auto 0;
      color: var(--muted);
      font-size: 1.05rem;
      line-height: 1.55;
    }

    .stats {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 0.75rem;
      margin: 2rem 0 0;
    }

    .stat {
      background: var(--chip);
      border: 1px solid var(--line);
      border-radius: var(--radius);
      padding: 1rem 0.85rem;
      text-align: center;
      backdrop-filter: blur(6px);
    }

    .stat strong {
      display: block;
      font-family: "Fraunces", Georgia, serif;
      font-size: 1.7rem;
      color: var(--gold-soft);
      line-height: 1;
    }

    .stat span {
      display: block;
      margin-top: 0.4rem;
      color: var(--muted);
      font-size: 0.78rem;
      letter-spacing: 0.04em;
      text-transform: uppercase;
    }

    .toolbar {
      position: sticky;
      top: 0.6rem;
      z-index: 20;
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem;
      align-items: center;
      justify-content: space-between;
      margin: 1.5rem 0 1.25rem;
      padding: 0.75rem 1rem;
      background: rgba(10, 42, 32, 0.88);
      border: 1px solid var(--line);
      border-radius: 16px;
      box-shadow: var(--shadow);
      backdrop-filter: blur(10px);
      animation: rise 0.8s ease 0.08s both;
    }

    .toolbar label {
      font-size: 0.85rem;
      color: var(--muted);
      font-weight: 600;
    }

    .toolbar select {
      appearance: none;
      border: 1px solid var(--line);
      background: var(--felt-mid) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath fill='%23e8c878' d='M1 1l5 5 5-5'/%3E%3C/svg%3E") right 0.8rem center / 12px no-repeat;
      color: var(--ink);
      border-radius: 12px;
      padding: 0.65rem 2.2rem 0.65rem 0.9rem;
      font: inherit;
      font-weight: 600;
      min-width: 12rem;
    }

    .toolbar select:focus {
      outline: 2px solid var(--gold);
      outline-offset: 2px;
    }

    .hint {
      color: var(--muted);
      font-size: 0.82rem;
    }

    section {
      margin: 2.25rem 0;
      animation: rise 0.75s ease both;
    }

    h2 {
      font-family: "Fraunces", Georgia, serif;
      font-size: clamp(1.5rem, 3vw, 2rem);
      font-weight: 700;
      margin: 0 0 0.35rem;
      letter-spacing: -0.02em;
    }

    .section-lede {
      margin: 0 0 1.1rem;
      color: var(--muted);
      max-width: 40rem;
      line-height: 1.5;
    }

    .roster {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
      gap: 0.65rem;
    }

    .player-chip {
      display: flex;
      align-items: center;
      gap: 0.65rem;
      padding: 0.7rem 0.8rem;
      background: var(--chip);
      border: 1px solid transparent;
      border-radius: 14px;
      cursor: pointer;
      text-align: left;
      color: inherit;
      font: inherit;
      transition: border-color 0.2s, transform 0.2s, background 0.2s;
    }

    .player-chip:hover,
    .player-chip.active {
      border-color: var(--gold);
      background: rgba(212, 168, 75, 0.12);
      transform: translateY(-1px);
    }

    .code {
      width: 1.7rem;
      height: 1.7rem;
      border-radius: 999px;
      display: grid;
      place-items: center;
      background: rgba(212, 168, 75, 0.18);
      color: var(--gold-soft);
      font-size: 0.75rem;
      font-weight: 700;
      flex-shrink: 0;
    }

    .player-chip strong {
      font-size: 0.92rem;
      font-weight: 600;
    }

    .md-nav {
      display: flex;
      flex-wrap: wrap;
      gap: 0.45rem;
      margin-bottom: 1rem;
    }

    .md-nav button {
      border: 1px solid var(--line);
      background: transparent;
      color: var(--muted);
      border-radius: 999px;
      padding: 0.45rem 0.85rem;
      font: inherit;
      font-size: 0.85rem;
      font-weight: 600;
      cursor: pointer;
      transition: 0.2s;
    }

    .md-nav button[aria-selected="true"] {
      background: var(--gold);
      color: var(--felt-deep);
      border-color: var(--gold);
    }

    .tables {
      display: grid;
      gap: 0.85rem;
    }

    @media (min-width: 800px) {
      .tables { grid-template-columns: 1.35fr 1fr 1fr; }
    }

    .table-card {
      border-radius: var(--radius);
      padding: 1rem 1.05rem 1.1rem;
      border: 1px solid var(--line);
      background: rgba(0, 0, 0, 0.18);
      transition: box-shadow 0.25s, border-color 0.25s, transform 0.25s;
    }

    .table-card.hit {
      border-color: var(--hl);
      box-shadow: 0 0 0 1px rgba(255, 224, 138, 0.35), var(--shadow);
      transform: translateY(-2px);
    }

    .table-card header {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 0.5rem;
      margin-bottom: 0.75rem;
    }

    .table-card h3 {
      margin: 0;
      font-size: 1rem;
      font-weight: 700;
    }

    .badge {
      font-size: 0.72rem;
      font-weight: 700;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      padding: 0.2rem 0.5rem;
      border-radius: 999px;
    }

    .table-card[data-kind="Big Six"] { border-top: 3px solid var(--six); }
    .table-card[data-kind="Orange"] { border-top: 3px solid var(--orange); }
    .table-card[data-kind="Blue"] { border-top: 3px solid var(--blue); }
    .table-card[data-kind="Big Six"] .badge { background: rgba(212,168,75,0.2); color: var(--gold-soft); }
    .table-card[data-kind="Orange"] .badge { background: rgba(196,92,38,0.25); color: #ffb089; }
    .table-card[data-kind="Blue"] .badge { background: rgba(42,111,151,0.3); color: #9fd0ef; }

    .seats {
      display: flex;
      flex-wrap: wrap;
      gap: 0.4rem;
    }

    .seat {
      padding: 0.35rem 0.65rem;
      border-radius: 999px;
      background: rgba(255,255,255,0.07);
      font-size: 0.86rem;
      font-weight: 600;
      border: 1px solid transparent;
    }

    .seat.me {
      background: var(--gold);
      color: var(--felt-deep);
      border-color: var(--gold-soft);
    }

    .my-card {
      display: none;
      border: 1px solid var(--line);
      border-radius: var(--radius);
      padding: 1.15rem 1.2rem;
      background: linear-gradient(145deg, rgba(212,168,75,0.14), rgba(0,0,0,0.2));
      box-shadow: var(--shadow);
    }

    .my-card.show { display: block; }

    .my-card h3 {
      margin: 0 0 0.25rem;
      font-family: "Fraunces", Georgia, serif;
      font-size: 1.45rem;
    }

    .my-grid {
      display: grid;
      gap: 0.55rem;
      margin-top: 1rem;
    }

    .my-row {
      display: grid;
      grid-template-columns: 3.2rem 1fr;
      gap: 0.75rem;
      align-items: start;
      padding: 0.65rem 0.75rem;
      background: rgba(0,0,0,0.18);
      border-radius: 12px;
    }

    .my-row .md {
      font-weight: 700;
      color: var(--gold-soft);
    }

    .my-row .meta {
      font-size: 0.8rem;
      color: var(--muted);
      margin-bottom: 0.2rem;
    }

    .rules {
      display: grid;
      gap: 0.7rem;
    }

    @media (min-width: 700px) {
      .rules { grid-template-columns: 1fr 1fr; }
    }

    .rule {
      padding: 1rem;
      border-radius: 14px;
      background: var(--chip);
      border: 1px solid var(--line);
    }

    .rule strong {
      display: block;
      margin-bottom: 0.3rem;
      color: var(--gold-soft);
    }

    .rule p {
      margin: 0;
      color: var(--muted);
      font-size: 0.92rem;
      line-height: 1.45;
    }

    footer {
      margin-top: 3rem;
      padding-top: 1.25rem;
      border-top: 1px solid var(--line);
      color: var(--muted);
      font-size: 0.85rem;
      text-align: center;
      line-height: 1.5;
    }

    @keyframes rise {
      from { opacity: 0; transform: translateY(12px); }
      to { opacity: 1; transform: none; }
    }

    @media (max-width: 700px) {
      .stats { grid-template-columns: 1fr 1fr; }
      .toolbar { align-items: stretch; }
      .toolbar > div { width: 100%; }
      .toolbar select { width: 100%; }
    }

    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        animation: none !important;
        transition: none !important;
      }
    }

    @media print {
      body { background: white; color: #111; }
      body::before, .toolbar { display: none; }
      .table-card, .stat, .player-chip, .rule, .my-card {
        break-inside: avoid;
        background: #f7f4ec;
        color: #111;
        border-color: #ccc;
      }
      .brand span, .stat strong, h2, .code { color: #8a6a20; }
      .muted, .lede, .section-lede, .hint, .rule p { color: #444; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <header class="hero">
      <p class="eyebrow">Official fixture · Share with the table</p>
      <h1 class="brand">Judgement<span>Premier League</span></h1>
      <p class="lede">Season 1 all-play-all. Fourteen players. Six matchdays. Three tables at once. Every rival across from you at least once.</p>
      <div class="stats" aria-label="Season snapshot">
        <div class="stat"><strong>14</strong><span>Players</span></div>
        <div class="stat"><strong>6</strong><span>Matchdays</span></div>
        <div class="stat"><strong>18</strong><span>Tables</span></div>
        <div class="stat"><strong>91</strong><span>Pairs covered</span></div>
      </div>
    </header>

    <div class="toolbar" role="search">
      <div>
        <label for="playerSelect">Find my schedule</label><br />
        <select id="playerSelect" aria-label="Select your name">
          <option value="">Everyone — full fixture</option>
        </select>
      </div>
      <p class="hint" id="focusHint">Tip: pick your name to highlight every table you sit at.</p>
    </div>

    <section aria-labelledby="roster-title">
      <h2 id="roster-title">The squad</h2>
      <p class="section-lede">Tap a player to focus their season. Codes A–N keep the sheet auditable.</p>
      <div class="roster" id="roster"></div>
    </section>

    <section aria-labelledby="mine-title" id="mineSection">
      <div class="my-card" id="myCard" aria-live="polite">
        <h3 id="mine-title">Your season card</h3>
        <p class="section-lede" id="myLede"></p>
        <div class="my-grid" id="myGrid"></div>
      </div>
    </section>

    <section aria-labelledby="fixture-title">
      <h2 id="fixture-title">Matchdays</h2>
      <p class="section-lede">Each sitting: <strong style="color:var(--gold-soft)">Big Six</strong> + <strong style="color:#ffb089">Orange</strong> + <strong style="color:#9fd0ef">Blue</strong> — start together, no byes.</p>
      <div class="md-nav" id="mdNav" role="tablist" aria-label="Matchday"></div>
      <div class="tables" id="tables" role="tabpanel"></div>
    </section>

    <section aria-labelledby="rules-title">
      <h2 id="rules-title">How we play it fair</h2>
      <p class="section-lede">House rules for a transparent league night.</p>
      <div class="rules">
        <div class="rule">
          <strong>Points series</strong>
          <p>Gold 500 · Silver 100 · Bronze 20. Attach every room to the live JPL tournament so scores land on the Tournament board.</p>
        </div>
        <div class="rule">
          <strong>No silent substitutes</strong>
          <p>Only the named fourteen. If someone can’t make it, reschedule that table — don’t quietly replace them.</p>
        </div>
        <div class="rule">
          <strong>Three rooms, one sitting</strong>
          <p>Open Big Six (6), Orange (4), and Blue (4) together. Same rules and round schedule on every table.</p>
        </div>
        <div class="rule">
          <strong>Everyone vs everyone</strong>
          <p>All 91 pairs share a table at least once. Some rematches (1–3×) — that’s the IPL rhythm, not a bug.</p>
        </div>
      </div>
    </section>

    <footer>
      Judgement Premier League — Season 1 · Generated from the official coverage sheet<br />
      Bid exact. Play brave. Brag in fifteen minutes. · #JudgementTable
    </footer>
  </div>

  <script id="jpl-data" type="application/json">__JPL_DATA__</script>
  <script>
    const DATA = JSON.parse(document.getElementById("jpl-data").textContent);
    const select = document.getElementById("playerSelect");
    const rosterEl = document.getElementById("roster");
    const mdNav = document.getElementById("mdNav");
    const tablesEl = document.getElementById("tables");
    const myCard = document.getElementById("myCard");
    const myGrid = document.getElementById("myGrid");
    const myLede = document.getElementById("myLede");
    const focusHint = document.getElementById("focusHint");

    let focus = "";
    let matchday = 1;

    DATA.roster.forEach((p) => {
      const opt = document.createElement("option");
      opt.value = p.name;
      opt.textContent = `${p.code} · ${p.name}`;
      select.appendChild(opt);

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "player-chip";
      btn.dataset.name = p.name;
      btn.innerHTML = `<span class="code">${p.code}</span><strong>${p.name}</strong>`;
      btn.addEventListener("click", () => setFocus(p.name));
      rosterEl.appendChild(btn);
    });

    DATA.matchdays.forEach((md) => {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = `MD ${md.n}`;
      b.setAttribute("role", "tab");
      b.setAttribute("aria-selected", md.n === 1 ? "true" : "false");
      b.addEventListener("click", () => {
        matchday = md.n;
        renderMatchday();
      });
      mdNav.appendChild(b);
    });

    select.addEventListener("change", () => setFocus(select.value));

    function setFocus(name) {
      focus = name || "";
      select.value = focus;
      [...rosterEl.children].forEach((el) => {
        el.classList.toggle("active", el.dataset.name === focus);
      });
      renderMatchday();
      renderMyCard();
      focusHint.textContent = focus
        ? `${focus}: your tables are highlighted below.`
        : "Tip: pick your name to highlight every table you sit at.";
    }

    function renderMatchday() {
      [...mdNav.children].forEach((b, i) => {
        b.setAttribute("aria-selected", i + 1 === matchday ? "true" : "false");
      });
      const md = DATA.matchdays.find((m) => m.n === matchday);
      tablesEl.innerHTML = "";
      md.tables.forEach((t) => {
        const hit = focus && t.players.includes(focus);
        const card = document.createElement("article");
        card.className = "table-card" + (hit ? " hit" : "");
        card.dataset.kind = t.label;
        card.innerHTML = `
          <header>
            <h3>${t.label}</h3>
            <span class="badge">${t.size} seats</span>
          </header>
          <div class="seats">
            ${t.players.map((p) =>
              `<span class="seat${p === focus ? " me" : ""}">${p}</span>`
            ).join("")}
          </div>`;
        tablesEl.appendChild(card);
      });
    }

    function renderMyCard() {
      if (!focus || !DATA.cards[focus]) {
        myCard.classList.remove("show");
        return;
      }
      const card = DATA.cards[focus];
      myCard.classList.add("show");
      myLede.textContent = `${card.games} games · full coverage of all 13 rivals · code ${card.code}`;
      myGrid.innerHTML = card.matchdays.map((row) => `
        <div class="my-row">
          <div class="md">MD ${row.matchday}</div>
          <div>
            <div class="meta">${row.table} · ${row.size} seats</div>
            <div>${row.opponents.join(" · ")}</div>
          </div>
        </div>`).join("");
    }

    renderMatchday();
  </script>
</body>
</html>
