# Chromium Text Field Smoke Result

Date: 2026-06-27T14:40:50.9477921-07:00

Status: passed

Browser: C:\Program Files\Google\Chrome\Application\chrome.exe

Input: `ngohaig` followed by space.

Input method: Win32 virtual-key typed test input.

Candidate-display screenshot: candidate-display-chromium.png.

Candidate-display screenshot captured: True

Commit screenshot: chromium-commit.png.

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

Chromium text-field click verified before typing: True

Chromium textarea focus verified before typing: True

Chromium event title after typing: YuneWindows Chromium Smoke - Textarea Focused - keydown=4 beforeinput=2 input=2 compositionstart=0 compositionupdate=0 compositionend=0 value_len=0

Chromium event title after commit: YuneWindows Chromium Smoke - Textarea Focused - keydown=5 beforeinput=4 input=4 compositionstart=1 compositionupdate=2 compositionend=1 value_len=3

Chromium event summary after typing: focused=true, keydown=4, beforeinput=2, input=2, compositionstart=0, compositionupdate=0, compositionend=0, value_len=0

Chromium event summary after commit: focused=true, keydown=5, beforeinput=4, input=4, compositionstart=1, compositionupdate=2, compositionend=1, value_len=3

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
