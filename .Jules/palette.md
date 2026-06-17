## 2024-05-24 - Accessibility: Missing tooltips on icon-only buttons
**Learning:** Found a widespread pattern of icon-only `IconButton` widgets lacking `tooltip` properties across the application. This makes navigation and interaction difficult for screen reader users and those relying on mouse hover hints.
**Action:** Implemented a standard to always include a descriptive `tooltip` string on all `IconButton` instances that don't have accompanying text labels, significantly improving app accessibility.
