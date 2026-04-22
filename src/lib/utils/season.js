export function seasonStart(refDate = new Date()) {
  const d = new Date(refDate);
  const y = d.getFullYear();
  const m = d.getMonth();
  const startYear = m >= 7 ? y : y - 1;
  return `${startYear}-08-01`;
}
