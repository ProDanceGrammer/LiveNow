LiveNow for Windows (portable)

1. Unzip the whole LiveNow folder anywhere (keep the files together).
2. Run livenow.exe.
   Windows SmartScreen may say "Windows protected your PC" because the app is
   not signed: choose More info > Run anyway.

Your data lives in %APPDATA%\io.livenow\livenow\ (one SQLite file per account).
Back it up from Settings, or copy that folder, before replacing LiveNow with a
newer version. To update, unzip the new build over the old folder.

Optional: sync hub. livenow.exe --hub runs the same program without a window
as an always-on sync hub (port 47653) that your phone and other PCs can reach.
  - Install (always on, starts at Windows login): double-click install_hub.cmd
    and accept the administrator (UAC) prompt. It copies the app to
    %LOCALAPPDATA%\LiveNowHub\app, so you may move or delete this folder after.
  - Uninstall: double-click uninstall_hub.cmd (the hub's data is kept).
  - Just try it once, no install: double-click start_hub.cmd (close its window
    to stop the hub).
Notes:
  - A plain LiveNow window finds the hub only through the default hub folder
    (%APPDATA%\io.livenow\livenow\hub). A hub started with a custom --hub-dir or
    LIVENOW_HUB_DIR is hidden from it.
  - The hub and a LiveNow window can run side by side (separate databases).
  - After unzipping a newer version, run install_hub.cmd again to update the hub.
