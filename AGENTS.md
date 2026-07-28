# Ambient Ops Display Contract

- Every new display page must be designed and verified first for the deployed HTC 5G Hub kiosk: 1280x720 physical pixels, landscape, 640x360 CSS viewport, and Android Kiosk with system animations disabled.
- A display page must remain a single non-scrolling screen on that target. Verify no clipped, overlapping, or hidden primary content with an ADB screenshot before delivery.
- Motion that communicates live state on the kiosk must not rely only on CSS animations. Use a deterministic time-driven path that still works when `prefers-reduced-motion` is reported because Android animation scales are disabled.
