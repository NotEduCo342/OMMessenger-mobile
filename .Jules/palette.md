## 2024-05-17 - Added Tooltips to Chat Action Buttons
**Learning:** Icon-only buttons (like attach file and send message) in the chat input area lacked tooltips, making them potentially ambiguous for some users and inaccessible to screen readers.
**Action:** Always verify that `IconButton` widgets used for primary actions have descriptive `tooltip` properties set for better accessibility.
