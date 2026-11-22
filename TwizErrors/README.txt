TwizErrors 1.0.0 - quiets the game's error voice
=================================================

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
