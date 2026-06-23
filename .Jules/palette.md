## 2024-05-18 - Missing Tooltips on Icon-Only Buttons
**Learning:** Screen readers and users who rely on hints struggle to understand the purpose of icon-only `IconButton` and `FloatingActionButton` elements when the `tooltip` property is omitted. In this app, important interactions like "Attach Image", "Delete Chat", or "New Chat" were unclear to assistive technologies.
**Action:** Always provide concise, descriptive `tooltip` attributes to any icon-only interactive elements to ensure accessibility and clarity.
