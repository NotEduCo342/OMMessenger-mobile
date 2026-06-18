## 2024-05-16 - Add missing tooltip properties to icon buttons
**Learning:** Added tooltip properties to icon-only buttons in `lib/screens/chat_screen.dart` to improve accessibility for screen readers and usability for hover interactions. These were missing from essential chat functions like send, attach, and cancel edit.
**Action:** Always check `IconButton` and similar icon-only widgets for the `tooltip` property to ensure proper accessibility support.
