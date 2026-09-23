-- SPDX-License-Identifier: MIT
-- Run one installed Shortcut with no input through Shortcuts Events.
on run arguments
    if (count of arguments) is not 1 then error "Expected one Shortcut name."
    set shortcutName to item 1 of arguments

    using terms from application "Shortcuts"
        tell application "Shortcuts Events"
            set matchingShortcuts to every shortcut whose name is my shortcutName
            if (count of matchingShortcuts) is not 1 then error "Expected exactly one installed Shortcut."
            set installedShortcut to item 1 of matchingShortcuts
            return (run installedShortcut) as text
        end tell
    end using terms from
end run
