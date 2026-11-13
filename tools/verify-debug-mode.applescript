on counterIsVisible()
    tell application "System Events" to tell process "BTNotify"
        return exists static text "Updated" of scroll area 1 of group 1 of pop over 1 of menu bar 2
    end tell
end counterIsVisible

tell application "System Events"
    tell process "BTNotify"
        if (count of pop overs of menu bar 2) > 0 then click menu bar item 1 of menu bar 2
        click menu bar item 1 of menu bar 2
        delay 0.3
    end tell
end tell
if counterIsVisible() then error "FAIL: normal opening shows the debug counter"

tell application "System Events"
    tell process "BTNotify" to click menu bar item 1 of menu bar 2
    key down option
    try
        tell process "BTNotify" to click menu bar item 1 of menu bar 2
        key up option
    on error messageText number errorNumber
        key up option
        error messageText number errorNumber
    end try
    delay 0.3
end tell
if not counterIsVisible() then error "FAIL: Option-opening does not show the debug counter"

tell application "System Events" to tell process "BTNotify"
    click menu bar item 1 of menu bar 2
    click menu bar item 1 of menu bar 2
    delay 0.3
end tell
if counterIsVisible() then error "FAIL: debug counter persists after normal reopening"
return "PASS: counter appears only when opened with Option held"
