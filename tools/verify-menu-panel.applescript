-- Regression check for the real, running menu bar app. Requires Accessibility
-- permission for the terminal/agent that invokes osascript.
tell application "System Events"
    tell process "BTNotify"
        if (count of pop overs of menu bar 2) is 0 then
            click menu bar item 1 of menu bar 2
            delay 0.3
        end if
        if (count of pop overs of menu bar 2) is 0 then error "FAIL: status item did not open a popover"
        set panelSize to size of pop over 1 of menu bar 2
        if item 1 of panelSize < 300 or item 2 of panelSize < 200 then error "FAIL: accessory panel collapsed"
        tell scroll area 1 of group 1 of pop over 1 of menu bar 2
            if not (exists static text "BTNotify") then error "FAIL: panel content is blank"
            if not (exists button 1) then error "FAIL: refresh control is missing"
            if (count of static texts) < 5 then error "FAIL: panel content did not render"
        end tell
        return "PASS: native menu bar popover has usable dimensions and rendered controls"
    end tell
end tell
