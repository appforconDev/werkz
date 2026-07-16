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
}

export const defaultConfig: DaemonConfig = {
  trustThresholds: { read: 25, routine: 50, smallDiff: 75 },
  smallDiffMaxLines: 20,
  keyboardHoldSeconds: 300,
  awayHoldSeconds: 7200,
  terminalActivityWindowMinutes: 5,
  decisionDedupWindowSeconds: 120,
  routingLatencyBudgetMs: 50,
};
