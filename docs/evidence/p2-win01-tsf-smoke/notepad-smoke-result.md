# Notepad Smoke Result

Date: 2026-06-27T14:40:36.3058625-07:00

Status: passed

Input: `ngohaig` followed by space.

Input method: Win32 virtual-key typed test input.

Candidate-display screenshot: candidate-display-notepad.png.

Candidate-display screenshot captured: True

Commit screenshot: notepad-commit.png.

Commit screenshot captured: True

Candidate/commit screenshots distinct: True

Expected committed text:

``text
我係個
``

Observed clipboard text after select-all/copy:

``text
我係個
``

Pass: True

Raw ASCII observed: False

Foreground target verified before typing: True

Active profile verified before typing: True

Clipboard cleared before typing: True

Clipboard cleared after capture: True

Matches expected Yune commit: True

Structural candidate update observed: True

Structural candidate update candidate count positive: True

Structural commit event observed: True

Structural candidate window failure observed: False

Structural event matcher: exact event tokens

Structural event summary: candidate_update=7, commit_request=1, commit_text=1, key_down=7

Structural new log lines: 16
