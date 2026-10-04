# winget machine setup

Scripts to rebuild my Windows machine with [winget](https://learn.microsoft.com/windows/package-manager/winget/).

| File | What it does |
|---|---|
| [`packages.json`](packages.json) | Apps to install, grouped by category (winget and Microsoft Store) |
| [`setup.ps1`](setup.ps1) | Installs everything in `packages.json`, skipping anything already installed |
| [`audit.ps1`](audit.ps1) | Compares installed software against `packages.json` to keep the list up to date |
| [`MANUAL.md`](MANUAL.md) | Drivers and apps winget can't install, with where to get them |

## Setting up a new machine

1. Make sure winget works. It ships with Windows 11; if `winget --version` fails,
   update **App Installer** from the Microsoft Store.
2. Get this repo. A fresh machine won't have git yet, so download the zip:

   ```powershell
   irm https://github.com/theboyknowsclass/winget/archive/refs/heads/main.zip -OutFile winget.zip
   Expand-Archive winget.zip -DestinationPath .; cd winget-main
   ```

3. Allow local scripts for this session and run the setup:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\setup.ps1
   ```

4. Work through [`MANUAL.md`](MANUAL.md), starting with chipset and GPU drivers.

Some installers ask for UAC elevation as they go, so stay near the machine.
Re-running `setup.ps1` is safe because already-installed apps are skipped.

## Choosing what to install

```powershell
.\setup.ps1 -List                   # show every group and package
.\setup.ps1 -Group core,dev         # only these groups
.\setup.ps1 -Exclude gaming,media   # everything except these
.\setup.ps1 -WhatIf                 # dry run: show what would be installed
```

Groups: `windows`, `core`, `communication`, `dev`, `maker`, `utilities`,
`hardware`, `media`, `gaming`.

The `windows` group holds apps that ship with Windows 11 (Terminal, OneDrive, Outlook,
To Do, etc.). On a normal install they're already there and get skipped; they're
listed so they come back if a debloat tool like Winhance removed them. Skip them with
`-Exclude windows`.

## Keeping the list up to date

```powershell
.\audit.ps1        # winget/Store apps installed but not in packages.json
.\audit.ps1 -All   # also list software winget doesn't recognise (drivers, vendor tools)
```

For anything new, search for it and add it to the right group in `packages.json`:

```powershell
winget search "app name"
```

Store apps use their Store ID with `"source": "msstore"`:

```json
{ "id": "9NKSQGP7F2NH", "source": "msstore", "name": "WhatsApp" }
```

If an app isn't in either catalog, add it to `MANUAL.md` instead.

### What the audit categories mean

- **winget / msstore**: winget has matched the app to a catalog package and can install or upgrade it.
- **ARP**: installed with a traditional installer that winget can't match to a package. Usually drivers or vendor tools, though some (Brave, for example) are in the catalog under a different name.
- **MSIX**: a Store or packaged app winget can't match. Mostly built-in Windows components.

Runtimes and dependencies (VC++ redistributables, Windows App Runtime, .NET
desktop runtimes, etc.) are left out on purpose because the apps that need them install them.
