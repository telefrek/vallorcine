# Bug Fix Regression Rule

When a bug is identified and a test can be written for it, a regression test
MUST be added before the fix is considered complete. The test should fail
without the fix and pass with it. This applies to all bug fixes — scripts,
install, upgrade, commands, or any other component.
