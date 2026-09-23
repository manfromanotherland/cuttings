-- SPDX-License-Identifier: MIT
-- Read installed Shortcut metadata through Apple's background-only service.
on run arguments
    if (count of arguments) is not 1 then error "Expected one Shortcut name."
    set shortcutName to item 1 of arguments

    using terms from application "Shortcuts"
        tell application "Shortcuts Events"
            set matchingShortcuts to every shortcut whose name is my shortcutName
            set matchCount to count of matchingShortcuts
            if matchCount is not 1 then
                return (matchCount as text) & tab & tab & tab
            end if

            set installedShortcut to item 1 of matchingShortcuts
            return (matchCount as text) & tab & (id of installedShortcut as text) & tab & ¬
                (action count of installedShortcut as text) & tab & (accepts input of installedShortcut as text)
        end tell
    end using terms from
end run
