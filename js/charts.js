// Charts Module — Pure SVG/HTML charts (no dependencies)
const Charts = (() => {
  const COLORS = [
    "#6366f1",
    "#22c55e",
    "#ef4444",
    "#eab308",
    "#3b82f6",
    "#a855f7",
    "#f97316",
    "#ec4899",
    "#14b8a6",
    "#f43f5e",
    "#8b5cf6",
    "#06b6d4",
    "#84cc16",
    "#d946ef",
    "#0ea5e9",
  ];

  function formatCurrency(amount, currency = "INR") {
    if (currency === "INR") return "₹" + amount.toLocaleString("en-IN");
    if (currency === "USD") return "$" + amount.toLocaleString("en-US");
    return currency + " " + amount.toLocaleString();
  }

  function shortAmount(amount) {
    if (amount >= 100000) return "₹" + (amount / 100000).toFixed(1) + "L";
    if (amount >= 1000) return "₹" + (amount / 1000).toFixed(1) + "K";
    return "₹" + amount.toFixed(0);
  }

  // ─── Donut Chart ───
  function renderDonut(containerId, data) {
    const container = document.getElementById(containerId);
    if (!container || !data.length) {
      if (container)
        container.innerHTML =
          '<div class="empty-state"><div class="empty-icon">📊</div><div class="empty-desc">No data yet</div></div>';
      return;
    }

    const total = data.reduce((s, d) => s + d.value, 0);
    if (total === 0) return;

    // Take top 6, rest as "Other"
    let sorted = [...data].sort((a, b) => b.value - a.value);
    let display = sorted.slice(0, 6);
    const rest = sorted.slice(6).reduce((s, d) => s + d.value, 0);
    if (rest > 0) display.push({ label: "Other", value: rest });

    const size = 140;
    const cx = size / 2,
      cy = size / 2,
      r = 52,
      strokeWidth = 22;
    const circumference = 2 * Math.PI * r;

    let svgPaths = "";
    let offset = 0;

    display.forEach((item, i) => {
      const pct = item.value / total;
      const dashLen = pct * circumference;
      const gap = circumference - dashLen;
      const color = COLORS[i % COLORS.length];

      svgPaths += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" 
                stroke="${color}" stroke-width="${strokeWidth}" 
                stroke-dasharray="${dashLen} ${gap}" 
                stroke-dashoffset="${-offset}" 
                transform="rotate(-90 ${cx} ${cy})"
                style="transition: stroke-dashoffset 0.5s ease"/>`;
      offset += dashLen;
    });

    const centerText = shortAmount(total);

    const svg = `<svg class="donut-svg" viewBox="0 0 ${size} ${size}">
            <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#1e293b" stroke-width="${strokeWidth}"/>
            ${svgPaths}
            <text x="${cx}" y="${cy - 6}" text-anchor="middle" fill="#94a3b8" font-size="10">Total</text>
            <text x="${cx}" y="${cy + 12}" text-anchor="middle" fill="#e2e8f0" font-size="14" font-weight="700">${centerText}</text>
        </svg>`;

    const legend = display
      .map((item, i) => {
        const pct = ((item.value / total) * 100).toFixed(0);
        return `<div class="legend-item">
                <div class="legend-dot" style="background:${COLORS[i % COLORS.length]}"></div>
                <span class="legend-label">${item.label}</span>
                <span class="legend-value">${pct}%</span>
            </div>`;
      })
      .join("");

    container.innerHTML = `${svg}<div class="donut-legend">${legend}</div>`;
  }

  // ─── Bar Chart ───
  function renderBars(containerId, data, options = {}) {
    const container = document.getElementById(containerId);
    if (!container || !data.length) {
      if (container)
        container.innerHTML =
          '<div class="empty-state"><div class="empty-desc">No data</div></div>';
      return;
    }

    const maxVal = Math.max(...data.map((d) => d.value), 1);
    const barColor =
      options.color || "linear-gradient(180deg, #6366f1 0%, #818cf8 100%)";

    const bars = data
      .map((d) => {
        const heightPct = Math.max((d.value / maxVal) * 100, 3);
        return `<div class="bar-group">
                <div class="bar" style="height:${heightPct}%;background:${barColor}">
                    ${d.value > 0 ? `<span class="bar-value">${shortAmount(d.value)}</span>` : ""}
                </div>
                <span class="bar-label">${d.label}</span>
            </div>`;
      })
      .join("");

    container.innerHTML = bars;
  }

  // ─── Top List ───
  function renderTopList(containerId, data, maxItems = 5) {
    const container = document.getElementById(containerId);
    if (!container) return;

    if (!data.length) {
      container.innerHTML =
        '<div class="empty-state"><div class="empty-desc">No data</div></div>';
      return;
    }

    const maxVal = data[0]?.value || 1;

    const items = data
      .slice(0, maxItems)
      .map((item, i) => {
        const pct = Math.max((item.value / maxVal) * 100, 5);
        return `<div class="top-item">
                <div class="top-rank">${i + 1}</div>
                <div class="top-info">
                    <div class="top-name">${item.label}</div>
                    <div class="top-bar-bg"><div class="top-bar-fill" style="width:${pct}%;background:${COLORS[i % COLORS.length]}"></div></div>
                </div>
                <div class="top-amount" style="color:${COLORS[i % COLORS.length]}">${shortAmount(item.value)}</div>
            </div>`;
      })
      .join("");

    container.innerHTML = items;
  }

  return {
    renderDonut,
    renderBars,
    renderTopList,
    formatCurrency,
    shortAmount,
    COLORS,
  };
})();

if (typeof module !== "undefined" && module.exports) {
  module.exports = Charts;
}
