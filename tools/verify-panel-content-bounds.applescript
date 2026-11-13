on checkVisibleContent(expanded)
    tell application "System Events" to tell process "BTNotify"
        set panel to pop over 1 of menu bar 2
        set panelOrigin to position of panel
        set panelSize to size of panel
        set content to scroll area 1 of group 1 of panel
        set titleOrigin to position of static text "BTNotify" of content
        set quitOrigin to position of last button of content
        set quitSize to size of last button of content
        set topGap to (item 2 of titleOrigin) - (item 2 of panelOrigin)
        set footerBottom to (item 2 of quitOrigin) + (item 2 of quitSize)
        set panelBottom to (item 2 of panelOrigin) + (item 2 of panelSize)
        if topGap < 8 or topGap > 45 then error "FAIL: header shifted or clipped; top gap=" & topGap
        if footerBottom > panelBottom - 8 then error "FAIL: footer clipped by popover"
        if expanded then
            set testButton to first button of content whose help is "Send a test notification"
            set testOrigin to position of testButton
            set testSize to size of testButton
            if (item 2 of testOrigin) + (item 2 of testSize) > panelBottom - 8 then error "FAIL: expanded settings are clipped"
        end if
    end tell
end checkVisibleContent

tell application "System Events" to tell process "BTNotify"
    if (count of pop overs of menu bar 2) is 0 then
        click menu bar item 1 of menu bar 2
        delay 0.5
    end if
    set disclosure to first UI element of scroll area 1 of group 1 of pop over 1 of menu bar 2 whose role is "AXDisclosureTriangle"
    if value of disclosure is true then click disclosure
end tell
delay 0.5
checkVisibleContent(false)
tell application "System Events" to tell process "BTNotify" to click disclosure
delay 0.5
checkVisibleContent(true)
tell application "System Events" to tell process "BTNotify" to click disclosure
delay 0.5
checkVisibleContent(false)
return "PASS: header, footer, and settings stay inside the popover"
