# Johnny's AltTab

What's different?
- Grouped List: Optionally add rules to match windows and add them to a group in the list (for example, you can add a rule to put all browser windows under "Browser Tabs", or all window titles matching "^Project:.\*" under "Projects"
- Includes browser tabs in the list, like how supasidebar does it. Also includes any other apps that use native macOS tabs (like Ghostty)

Planned Features In order of priority:
- If cmd is held the whole time while tabbing, then releasing it triggers the selection (like how normal cmd tab works. So a quick cmd+tab can toggle back and forth between apps). If cmd+tab is pressed and released without tabbing, then it stays open for search
- add custom "trigger" menu items that open deeplinks/x-callback-urls. So you can have things like a "new note" or "new browser window" action that can be selected and triggered right from alt tab
- bangs to filter within group (e.g. searching "@tabs my query" will filter the search to only the Tabs section). Also can add aliases so @t could filter tabs.
  - would be nice to have a filter toggle down to the current project too, but would need a canonical way to represent a project. Easy-ish if I commit to Expanse Frames being the unit of a Project... but not sure if I'll stick with expanse or if it's just a gimmick right now. Could get most of the functionality just using macOS native spaces
- config via a toml dotfile instead of a gui
