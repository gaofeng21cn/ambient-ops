const KIOSK_USER_AGENT = /\bAmbientOpsKiosk\//;

export function shouldReduceKioskMotion(userAgent, prefersReducedMotion) {
  return Boolean(prefersReducedMotion) && !KIOSK_USER_AGENT.test(userAgent || "");
}
