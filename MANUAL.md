# Manual installs

Software on this machine that winget can't install (not in the winget or
Microsoft Store catalogs, or it's a hardware driver). Install these by hand
after running `setup.ps1`.

## Drivers and motherboard (GIGABYTE / AMD)

| Software | Where to get it | Notes |
|---|---|---|
| AMD Chipset Software | [amd.com/support](https://www.amd.com/en/support/download/drivers.html) | Install first, before other drivers |
| AMD Software (Adrenalin) / Radeon Software | [amd.com/support](https://www.amd.com/en/support/download/drivers.html) | Only needed for the CPU's integrated graphics |
| AMD Ryzen Master | [amd.com/ryzen-master](https://www.amd.com/en/products/software/ryzen-master.html) | Optional, for tuning |
| GIGABYTE Control Center | GIGABYTE motherboard support page | Pulls in GBT RGB / Dynamic Lighting / Performance / Storage libraries, Wi-Fi Compass and A.I. Snatch |
| Realtek Audio Driver + Audio Control | GIGABYTE motherboard support page | Audio Control app comes with the driver |
| Realtek Ethernet Controller Driver | GIGABYTE motherboard support page | Windows Update usually covers it |
| NVIDIA Graphics Driver | Installed through **NVIDIA App** (`hardware` group) | Includes HD Audio driver and FrameView SDK |

## Peripherals and devices

| Software | Where to get it | Notes |
|---|---|---|
| Corsair Device Control Service | [corsair.com/downloads](https://www.corsair.com/downloads) | Only if you have Corsair hardware (RAM, cooler, fans). May also be pulled in by GIGABYTE Control Center's RGB module. For full iCUE: `winget install Corsair.iCUE.5` |
| L-Connect 3 **beta** (2.x, OpenRGB support) | [lian-li.com/l-connect3](https://lian-li.com/l-connect3/) | Lian Li fans/RGB. winget only has the old stable 1.6.30 (`LianLi.LConnect3`), so install the beta by hand |
| Epson ET-5170 printer driver + PC-FAX / FAX Utility | [epson.com support](https://epson.com/Support/sl/s) | Epson scan/connect tools are in the `hardware` group |

## Apps

| Software | Where to get it | Notes |
|---|---|---|
| Microsoft 365 (Family/Personal) | [microsoft365.com](https://www.microsoft365.com/) → Install apps | `Microsoft.Office` in winget is the enterprise build |
| Makera Studio | [makera.com](https://www.makera.com/) | Makera CNC software |
| GridfinityGenerator | Original source | Not in any public catalog |

## Installed automatically by something else

You don't need to install these yourself:

- **Logi Plugin Service** comes with Logi Options+
- **ENE / WD P40 Game Drive / Verbatim SureFire HALs** are RGB device plugins installed by GIGABYTE Control Center's RGB module
- **Local AI Manager, Office Actions Server, push notifications** come with Microsoft 365
- **Virtual Desktop Service** comes with Virtual Desktop Streamer
- **iCloud Outlook** comes with iCloud
- Store/built-in apps (Photos, Calculator, Snipping Tool, codec extensions, etc.) come with Windows
