/**
 * @jest-environment jsdom
 */

// Charts Module Tests
const Charts = require("../js/charts");

describe("Charts", () => {
  // ─── Module API ───
  describe("Module exports", () => {
    test("exposes formatCurrency", () => {
      expect(typeof Charts.formatCurrency).toBe("function");
    });
    test("exposes shortAmount", () => {
      expect(typeof Charts.shortAmount).toBe("function");
    });
    test("exposes renderDonut", () => {
      expect(typeof Charts.renderDonut).toBe("function");
    });
    test("exposes renderBars", () => {
      expect(typeof Charts.renderBars).toBe("function");
    });
    test("exposes renderTopList", () => {
      expect(typeof Charts.renderTopList).toBe("function");
    });
    test("exposes COLORS array", () => {
      expect(Array.isArray(Charts.COLORS)).toBe(true);
      expect(Charts.COLORS.length).toBe(15);
    });
  });

  // ─── formatCurrency ───
  describe("formatCurrency", () => {
    test("formats INR correctly", () => {
      const result = Charts.formatCurrency(1000, "INR");
      expect(result).toContain("₹");
      expect(result).toContain("1,000");
    });
    test("formats USD correctly", () => {
      const result = Charts.formatCurrency(1000, "USD");
      expect(result).toContain("$");
      expect(result).toContain("1,000");
    });
    test("formats other currencies", () => {
      const result = Charts.formatCurrency(1000, "EUR");
      expect(result).toContain("EUR");
    });
    test("defaults to INR", () => {
      const result = Charts.formatCurrency(500);
      expect(result).toContain("₹");
    });
    test("handles zero", () => {
      expect(Charts.formatCurrency(0, "INR")).toContain("₹");
      expect(Charts.formatCurrency(0, "INR")).toContain("0");
    });
    test("handles large INR numbers with Indian formatting", () => {
      const result = Charts.formatCurrency(1250000, "INR");
      expect(result).toContain("₹");
      // Indian format: 12,50,000
      expect(result).toContain("12,50,000");
    });
  });

  // ─── shortAmount ───
  describe("shortAmount", () => {
    test("formats lakhs (>=100000)", () => {
      expect(Charts.shortAmount(150000)).toBe("₹1.5L");
    });
    test("formats thousands (>=1000)", () => {
      expect(Charts.shortAmount(5000)).toBe("₹5.0K");
    });
    test("formats small amounts (<1000)", () => {
      expect(Charts.shortAmount(500)).toBe("₹500");
    });
    test("formats exact lakh", () => {
      expect(Charts.shortAmount(100000)).toBe("₹1.0L");
    });
    test("formats exact thousand", () => {
      expect(Charts.shortAmount(1000)).toBe("₹1.0K");
    });
    test("formats zero", () => {
      expect(Charts.shortAmount(0)).toBe("₹0");
    });
    test("formats amount just under 1000", () => {
      expect(Charts.shortAmount(999)).toBe("₹999");
    });
    test("formats 10 lakhs (1 million)", () => {
      expect(Charts.shortAmount(1000000)).toBe("₹10.0L");
    });
  });

  // ─── renderDonut ───
  describe("renderDonut", () => {
    let container;

    beforeEach(() => {
      container = document.createElement("div");
      container.id = "testDonut";
      document.body.appendChild(container);
    });

    afterEach(() => {
      document.body.removeChild(container);
    });

    test("renders SVG for valid data", () => {
      Charts.renderDonut("testDonut", [
        { label: "Food", value: 500 },
        { label: "Shopping", value: 300 },
      ]);
      expect(container.innerHTML).toContain("<svg");
      expect(container.innerHTML).toContain("circle");
    });

    test("renders empty state for empty data", () => {
      Charts.renderDonut("testDonut", []);
      expect(container.innerHTML).toContain("empty-state");
    });

    test("renders legend items", () => {
      Charts.renderDonut("testDonut", [
        { label: "Food", value: 500 },
        { label: "Shopping", value: 300 },
      ]);
      expect(container.innerHTML).toContain("Food");
      expect(container.innerHTML).toContain("Shopping");
    });

    test("groups items after 6 into Other", () => {
      const data = [];
      for (let i = 0; i < 9; i++) {
        data.push({ label: `Cat${i}`, value: 100 * (i + 1) });
      }
      Charts.renderDonut("testDonut", data);
      expect(container.innerHTML).toContain("Other");
    });

    test("handles single category", () => {
      Charts.renderDonut("testDonut", [{ label: "Only Item", value: 1000 }]);
      expect(container.innerHTML).toContain("<svg");
      expect(container.innerHTML).toContain("Only Item");
    });

    test("does nothing for non-existent container", () => {
      // Should not throw
      expect(() => {
        Charts.renderDonut("nonExistent", [{ label: "Food", value: 500 }]);
      }).not.toThrow();
    });

    test("renders total in center", () => {
      Charts.renderDonut("testDonut", [
        { label: "Food", value: 5000 },
        { label: "Transport", value: 3000 },
      ]);
      expect(container.innerHTML).toContain("₹8.0K");
    });
  });

  // ─── renderBars ───
  describe("renderBars", () => {
    let container;

    beforeEach(() => {
      container = document.createElement("div");
      container.id = "testBars";
      document.body.appendChild(container);
    });

    afterEach(() => {
      document.body.removeChild(container);
    });

    test("renders bars for valid data", () => {
      Charts.renderBars("testBars", [
        { label: "1", value: 500 },
        { label: "2", value: 300 },
        { label: "3", value: 800 },
      ]);
      expect(container.innerHTML).toContain("bar-group");
    });

    test("renders empty state for empty data", () => {
      Charts.renderBars("testBars", []);
      expect(container.innerHTML).toContain("empty-state");
    });

    test("renders labels", () => {
      Charts.renderBars("testBars", [
        { label: "Mon", value: 500 },
        { label: "Tue", value: 300 },
      ]);
      expect(container.innerHTML).toContain("Mon");
      expect(container.innerHTML).toContain("Tue");
    });

    test("handles zero values", () => {
      Charts.renderBars("testBars", [
        { label: "1", value: 0 },
        { label: "2", value: 500 },
      ]);
      expect(container.innerHTML).toContain("bar-group");
    });

    test("accepts custom color option", () => {
      Charts.renderBars("testBars", [{ label: "1", value: 500 }], {
        color: "linear-gradient(180deg, #22c55e 0%, #16a34a 100%)",
      });
      expect(container.innerHTML).toContain("#22c55e");
    });
  });

  // ─── renderTopList ───
  describe("renderTopList", () => {
    let container;

    beforeEach(() => {
      container = document.createElement("div");
      container.id = "testTopList";
      document.body.appendChild(container);
    });

    afterEach(() => {
      document.body.removeChild(container);
    });

    test("renders top items", () => {
      Charts.renderTopList("testTopList", [
        { label: "Swiggy", value: 5000 },
        { label: "Amazon", value: 3000 },
      ]);
      expect(container.innerHTML).toContain("Swiggy");
      expect(container.innerHTML).toContain("Amazon");
    });

    test("limits to maxItems", () => {
      const data = [];
      for (let i = 0; i < 10; i++) {
        data.push({ label: `Item${i}`, value: 1000 - i * 100 });
      }
      Charts.renderTopList("testTopList", data, 3);
      expect(container.innerHTML).toContain("Item0");
      expect(container.innerHTML).toContain("Item2");
      expect(container.innerHTML).not.toContain("Item3");
    });

    test("renders empty state for empty data", () => {
      Charts.renderTopList("testTopList", []);
      expect(container.innerHTML).toContain("empty-state");
    });

    test("renders rank numbers", () => {
      Charts.renderTopList("testTopList", [
        { label: "First", value: 1000 },
        { label: "Second", value: 500 },
      ]);
      expect(container.innerHTML).toContain("1");
      expect(container.innerHTML).toContain("2");
    });
  });
});
