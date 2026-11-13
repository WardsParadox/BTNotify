tell application "System Events"
    tell process "BTNotify"
        if (count of pop overs of menu bar 2) is 0 then
            click menu bar item 1 of menu bar 2
            delay 0.3
        end if
        set disclosure to first UI element of scroll area 1 of group 1 of pop over 1 of menu bar 2 whose role is "AXDisclosureTriangle"
        if value of disclosure is true then click disclosure
        delay 0.3
        set panelSize to size of pop over 1 of menu bar 2
        set collapsedHeight to item 2 of panelSize
        click disclosure
        delay 0.3
        set panelSize to size of pop over 1 of menu bar 2
        set expandedHeight to item 2 of panelSize
        tell scroll area 1 of group 1 of pop over 1 of menu bar 2
            if exists static text "macOS notifications allowed." then
                if exists button "Allow Notifications" then error "FAIL: authorization button is visible despite granted permission"
            end if
        end tell
        click disclosure
        delay 0.3
        set panelSize to size of pop over 1 of menu bar 2
        set restoredHeight to item 2 of panelSize
        if expandedHeight ≤ collapsedHeight + 20 then error "FAIL: settings expansion did not grow the panel (" & collapsedHeight & " → " & expandedHeight & ")"
        if restoredHeight ≥ expandedHeight - 20 then error "FAIL: settings collapse did not shrink the panel"
        return "PASS: panel resizes " & collapsedHeight & " → " & expandedHeight & " → " & restoredHeight
    end tell
end tell
