## 2024-05-24 - Add Tooltips to Icon-Only Buttons
**Learning:** Icon-only buttons without explicit 'tooltip' or semantic labels are entirely opaque to screen readers, severely hurting accessibility. In Flutter, the 'IconButton' widget does not automatically infer a meaningful label from its icon.
**Action:** Always provide a descriptive 'tooltip' property for 'IconButton' and other icon-only interactive widgets to ensure they are accessible via screen readers and provide hover hints for desktop users.
