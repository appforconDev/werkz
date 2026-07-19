// Daemon config with defaults. Values here mirror event-model.md; in P1 these
// load from the paired config file. Trust thresholds are GDD §4.1 starting
// values, tunable for beta calibration.

export interface DaemonConfig {
  trustThresholds: { read: number; routine: number; smallDiff: number };
  smallDiffMaxLines: number;
  keyboardHoldSeconds: number;   // §3.4 ceiling at the keyboard
  awayHoldSeconds: number;       // §3.4 ceiling when phone is the surface (confirmed honored to 7200)
  terminalActivityWindowMinutes: number;
  decisionDedupWindowSeconds: number; // §3.6
  routingLatencyBudgetMs: number;     // §3.5 HARD RULE
  // Task 17 A2: any pending decision older than this is a zombie — no
  // legitimate hold ceiling reaches it (away ceiling is 2h). Swept on a timer.
  pendingTtlHours: number;
}

export const defaultConfig: DaemonConfig = {
  // read: 0 (task 27 calibration, sanctioned by GDD §4.1 "starting values;
  // calibrate"): reads are side-effect-free, and gating them at 25 made a
  // fresh workshop (trust 0) hold/deny EVERY pwd/ls/Read — a read-only audit
  // produced nothing but rejections. Reads auto-allow from trust 0; the trust
  // ladder governs writes (routine 50, small-diff 75; destructive NEVER auto).
  trustThresholds: { read: 0, routine: 50, smallDiff: 75 },
  smallDiffMaxLines: 20,
  keyboardHoldSeconds: 300,
  awayHoldSeconds: 7200,
  terminalActivityWindowMinutes: 5,
  decisionDedupWindowSeconds: 120,
  routingLatencyBudgetMs: 50,
  pendingTtlHours: 3,
};
