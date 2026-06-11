## 2026-06-11 - Added tooltips to icon-only buttons
**Learning:** Flutter's `IconButton` widget doesn't automatically derive screen reader labels or visual tooltips unless explicitly provided. Many crucial actions (like sending messages or clearing searches) were icon-only, lacking context for screen readers and desktop/web hover states.
**Action:** Always provide a descriptive `tooltip` parameter when implementing `IconButton` or other icon-only interactive widgets in Flutter to ensure both accessibility and usability.
