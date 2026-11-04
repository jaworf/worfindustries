# Version 1.3 build 21

Candidate notes now include an iOS keyboard toolbar Done button. Dragging the candidate form dismisses the keyboard interactively, and saving a call clears note-field focus. Return still allows multiline notes.

The existing Finish Recruiting action is labeled Close Opening on iPhone/iPad and web. It uses the same checked server command: the opening moves to Completed and candidate/call history is retained. Pending nominations must be resolved or withdrawn before closing. The web card-collapse control is labeled Collapse Details, with explanatory completion text nearby.

Validation: all 23 native tests passed on the macOS destination; signed iOS archive succeeded; all 96 backend/component tests passed. The image-rendering test helper now writes to the app's temporary directory so it works with the macOS sandbox. iOS simulator testing is unavailable because the installed CoreSimulator framework is older than this Xcode version. Physical-device keyboard dismissal still needs a TestFlight check.

Build 21 is intended for TestFlight verification. Build 20 was submitted for public App Store review on November 4, 2026, with automatic release after approval.
