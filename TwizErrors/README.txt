TwizErrors 1.1.0 - quiets the game's error voice, catches Lua errors
===================================================================

Stops your character from saying "Not enough mana", "Not enough energy",
"I can't do that yet", "Another action is in progress" and the rest of the
spoken errors. Works on load - nothing to set up.

How: it turns off the game's own "error speech" setting (Sound_EnableErrorSpeech).
That silences every spoken error; game sounds, music and other voices are not
touched. Turning TwizErrors off puts your old setting back.

Optional: /terr text also hides the RED TEXT for the spammy errors (out of
mana/energy/rage, not ready yet, can't do that yet, another action in
progress, out of range, facing, no target, moving). Every other error message
still shows.

Commands
  /terr          silence on/off
  /terr text     also hide the red text for those errors (on/off)
  /terr status   what's on

ERROR CATCHER (1.1.0) - BugSack built in
  Every Lua error and blocked action from ANY addon is caught and saved
  (last 100), with the addon it came from, the time, how many times it
  happened and the full stack. A chat line tells you when one is caught (at
  most every 30 sec). The same error repeating is counted, not listed again.
  /terr bugs opens the window: Newer / Older to step through, "Select all"
  then Ctrl+C to copy the whole thing (paste it to Claude to get it fixed).
  The TwizForever menu shows each Twiz addon's error count.
  /terr bugs       the window
  /terr clear      forget saved errors
  /terr catch      catching on/off
  /terr quietbugs  no chat line when one is caught
