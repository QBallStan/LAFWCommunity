# API evidence

2026-11-02: Installation .build.info reports Retail 12.1.5.70688. Corrected manifest interface to 120105 (12 * 10000 + 1 * 100 + 5), matching installed current TradeSkillMaster manifests. Retail gx.log also confirms running build 12.1.5.70688. GetBuildInfo confirmation in game remains pending.

No in-game validation performed. C_Club calls are guarded and their return values are treated as partial observations. Faction enum availability is checked; no numeric mapping is guessed.

Required next checks: addon load, actual interface number, subscribed community types, member field completeness, faction enum mapping, opposite-faction visibility, delayed roster readiness, reload persistence, large roster scrolling, combat UI behavior.

Chat selection remains unresolved: community stream versus custom channel. Chat mutations, identity decoration, professions and synchronization are deferred pending API evidence and product decisions.
