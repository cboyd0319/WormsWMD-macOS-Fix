Worms W.M.D macOS Fix
=====================

Start here if Terminal feels like a bad place.

What to do
----------

1. Double-click "Worms W.M.D Fix.command".
2. Choose option 1: "Apply the recommended fix".
3. When it finishes, press Return to launch when prompted, or choose option 7
   later.

Want to verify the zip first?
-----------------------------

If you downloaded the matching ".zip.sha256" file next to this zip, open
Terminal in your Downloads folder and run this with the release version from
the filename:

    shasum -a 256 -c WormsWMD-macOS-Fix-VERSION.zip.sha256

It should print:

    WormsWMD-macOS-Fix-VERSION.zip: OK

If macOS blocks the file
------------------------

Right-click "Worms W.M.D Fix.command", choose Open, then choose Open again.
This is the normal Gatekeeper warning for downloaded community scripts.

If something fails
------------------

Run "Worms W.M.D Fix.command" again and choose option 5. It creates a support
bundle on your Desktop without raw logs, save files, or game config files.
Attach that file to a GitHub issue:

https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues

What this changes
-----------------

The fix updates files inside the Worms W.M.D app bundle so the game can launch
on newer macOS versions. It creates backups before changing game-bundle files.
It does not use admin privileges, system-wide installers, telemetry, or account
collection.

Need to undo it?
----------------

Run "Worms W.M.D Fix.command" and choose option 4.
