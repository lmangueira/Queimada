# Distribution (U9 / R14–R15)

## Channels

- **Mac App Store** (gated on U1 spike GO): Apple handles payment, licensing,
  and updates. Sandboxed build (`app-mas`).
- **Direct download**: Developer ID signed + notarized DMG from the product
  site. Needs its own payment/licensing and update path.

## Direct-channel decisions (deferred from plan; settle before first sale)

- **Payment/licensing vendor**: Paddle, Lemon Squeezy, or Gumroad all handle
  VAT/receipts and license keys for solo developers. Decision pending.
- **License enforcement**: keep friction low — offline-verifiable signed
  license key, no activation server for v1.
- **Auto-update**: Sparkle 2 (sandbox-compatible, standard for direct macOS
  distribution). Add the framework only to the direct build; MAS updates are
  Apple's. Note: this is distribution plumbing, not a burning-engine
  dependency — R16 (no third-party *burning* library) is intact.

## Pricing posture (from the brainstorm)

Cheap, single-purpose, no subscription: the anti-bloatware position. One paid
tier, both channels at price parity.
