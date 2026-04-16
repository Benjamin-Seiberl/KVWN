// Einfacher CSV-Parser für Match-Imports
// Erwartet Header-Zeile mit diesen Spalten (flexibel):
//   date,time,league,home_away,opponent,location,round
// Trennzeichen: Komma oder Semikolon; Anführungszeichen optional

function splitLine(line, sep) {
  const out = [];
  let cur = '';
  let inQ = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') { inQ = !inQ; continue; }
    if (c === sep && !inQ) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  out.push(cur);
  return out.map(s => s.trim());
}

export function parseMatchesCsv(text) {
  const lines = text.split(/\r?\n/).filter(l => l.trim().length);
  if (lines.length < 2) return { rows: [], errors: ['CSV enthält keine Datenzeilen'] };
  const sep = lines[0].includes(';') ? ';' : ',';
  const header = splitLine(lines[0], sep).map(h => h.toLowerCase());
  const rows = [];
  const errors = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = splitLine(lines[i], sep);
    const obj = {};
    header.forEach((h, idx) => { obj[h] = cols[idx] ?? ''; });
    if (!obj.date || !obj.opponent) {
      errors.push(`Zeile ${i + 1}: date/opponent fehlt`);
      continue;
    }
    const ha = (obj.home_away || '').toUpperCase();
    rows.push({
      date:       obj.date,
      time:       obj.time || null,
      league:     obj.league || null,
      home_away:  ha === 'H' ? 'HEIM' : ha === 'A' ? 'AUSWÄRTS' : ha || null,
      opponent:   obj.opponent,
      location:   obj.location || null,
      round:      obj.round || null,
    });
  }
  return { rows, errors };
}
