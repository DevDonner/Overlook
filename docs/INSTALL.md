# Installing Overlook on WoW Forever

WoW Forever keeps its addons in its own folder, separate from retail and Classic:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\
```

(If you installed the game somewhere else, look for the `_forever_` folder inside your World of Warcraft folder.)

The one rule that matters: the addon must sit in a folder named exactly **`Overlook`**, with `Overlook.toc` directly inside it. The game skips any other folder name.

Close the game, or be ready to log out to the character screen, before you start.

## Option 1: download a ZIP (simplest)

1. Open https://github.com/DevDonner/Overlook while logged in to GitHub (the repo is private).
2. Click **Code → Download ZIP**.
3. Extract the ZIP. You get a folder called `Overlook-main`.
4. Rename it to **`Overlook`**.
5. Move it into `_forever_\Interface\AddOns\`.

To update, delete the old folder and repeat.

## Option 2: clone with Git (easy updates)

In PowerShell:

```powershell
cd "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
git clone https://github.com/DevDonner/Overlook.git
```

To update later, run `git pull` inside that folder, then `/reload` in game.

## Option 3: link to your working copy (for development)

If you edit the code somewhere else, link it into AddOns instead of copying. Every change then shows up after a `/reload`. In PowerShell:

```powershell
New-Item -ItemType Junction `
  -Path   "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Overlook" `
  -Target "C:\programming\code\wow-forever\addons\minimap"
```

Change `-Target` to wherever your copy lives. If you get "Access denied", run PowerShell as administrator. Deleting the link later removes only the link, not your code.

## Check it worked

1. Start WoW Forever. At the character screen, click **AddOns** (bottom left).
2. **Overlook** should be listed and ticked.
3. Log in and type `/overlook`. You should see the command list in chat.

Questie is optional, but most of the checks are about Questie's icons, so keep it enabled.

## If it doesn't show up

| Problem | Fix |
| --- | --- |
| Not in the AddOns list | Check the folder is named exactly `Overlook` and isn't nested (`Overlook\Overlook\...`). The `.toc` file must be directly inside. |
| Listed as "Out of date" or "Incompatible" | The game was patched past interface 16001. Tick **Load out of date AddOns**, and tell the developer. |
| `/overlook` does nothing | The addon is unticked in the AddOns list, or loaded with an error. Type `/console scriptErrors 1`, `/reload`, and note the error text. |
