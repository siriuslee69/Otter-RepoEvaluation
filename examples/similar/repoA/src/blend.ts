// Mixes two rows of pixel values by a weight. The same idea is written in
// JavaScript (repoB), Rust and Python (repoC) with other names.
export function blendRows(top: number[], bottom: number[], alpha: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < top.length; i++) {
    const a = top[i] * alpha;
    const b = bottom[i] * (1 - alpha);
    out.push(Math.round(a + b));
  }
  if (out.length === 0) {
    return [];
  }
  return out;
}

// Not like the others: reads "key: value" header lines.
export function readHeader(text: string): Map<string, string> {
  const found = new Map<string, string>();
  const lines = text.split("\n");
  let i = 0;
  while (i < lines.length) {
    const at = lines[i].indexOf(":");
    if (at > 0) {
      found.set(lines[i].slice(0, at).trim(), lines[i].slice(at + 1).trim());
    }
    i += 1;
  }
  return found;
}
