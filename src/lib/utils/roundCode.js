// Berechnet Rundencode aus Datum innerhalb einer Saison.
// Herbst = Sep-Dez → H01..HNN; Frühjahr = Jan-Mai → F01..FNN.
// Die Nummerierung folgt der Kalenderwoche relativ zum ersten Match der Saison.

export function roundCodeFor(date, seasonMatches) {
  if (!date) return null;
  const d = new Date(date);
  const month = d.getMonth(); // 0=Jan
  const prefix = month >= 8 ? 'H' : 'F'; // Sep-Dez = H, Jan-Mai = F

  // Sortiere alle Matches der Saison nach Datum
  const sameHalf = (seasonMatches || [])
    .filter(m => {
      const md = new Date(m.date);
      const mm = md.getMonth();
      return (prefix === 'H' ? mm >= 8 : mm < 8);
    })
    .sort((a, b) => new Date(a.date) - new Date(b.date));

  // Gruppiere nach Kalenderwoche → jede Woche = 1 Runde
  const weekKey = (dt) => {
    const dd = new Date(dt);
    dd.setHours(0, 0, 0, 0);
    dd.setDate(dd.getDate() + 3 - ((dd.getDay() + 6) % 7));
    const week1 = new Date(dd.getFullYear(), 0, 4);
    return dd.getFullYear() + '-' + (1 + Math.round(((dd - week1) / 86400000 - 3 + ((week1.getDay() + 6) % 7)) / 7));
  };

  const weeks = [];
  for (const m of sameHalf) {
    const k = weekKey(m.date);
    if (!weeks.includes(k)) weeks.push(k);
  }
  const idx = weeks.indexOf(weekKey(date));
  if (idx < 0) return null;
  return `${prefix}${String(idx + 1).padStart(2, '0')}`;
}
