# Copernicus temperature/salinity data sources

This package lets you choose **one of two Copernicus Marine (CMEMS) multi‑year global reanalysis products** as a backend for **temperature** and **salinity** fields.

> TL;DR —
>
> - `` → single‑model GLORYS12V1, **1/12° (\~8 km)**, 50 z‑levels, 1992→present (via interim). Use variables `temperature` and `salinity`.
> - ``\*\* (GREP)\*\* → **ensemble** of 3 reanalyses on a **0.25°** grid with 75 z‑levels, 1993→present. Prefer the **ensemble means**: `temperature_mean`, `salinity_mean`.

---

## 1) Choose a source

```yaml
# example config
source: 001-030   # or: 001-031
variable: temperature   # one of: temperature | salinity | temperature_mean | salinity_mean
cadence: daily          # one of: daily | monthly (availability depends on source)
```

### When to prefer which

- **001‑030 (GLORYS12V1)** — choose when **finer spatial detail** matters (eddies, boundary currents, coastal applications) and you’re OK with a single reanalysis.
- **001‑031 (GREP ensemble)** — choose when you value **ensemble mean & spread** (uncertainty) and are fine with **coarser 0.25°** resolution.

---

## 2) Coverage & resolution

| Product key | Human name                                              | Grid (lon/lat)     | Vertical levels | Time coverage†                                                            | Cadence         |
| ----------- | ------------------------------------------------------- | ------------------ | --------------- | ------------------------------------------------------------------------- | --------------- |
| `001-030`   | Global Ocean Physical **Multi‑Year** (GLORYS12V1)       | **1/12° (\~8 km)** | **50**          | **1992‑06‑04 → 2021‑06‑31** (reanalysis) + **2021‑07‑01 → M‑1** (interim) | daily & monthly |
| `001-031`   | Global Ocean **Reanalysis Multi‑Model Ensemble** (GREP) | **0.25°**          | **75**          | **1993‑01‑01 →** (multi‑decadal; updated)                                 | daily & monthly |

†Exact end dates roll as CMEMS updates the catalog.

---

## 3) Variables exposed by this package

To keep a simple, backend‑agnostic API, the package exposes **four** variable ids:

- `temperature`  → 3‑D potential temperature (°C)
- `salinity`     → 3‑D practical salinity (PSU)
- `temperature_mean` → ensemble‑mean temperature (only meaningful for **001‑031**)
- `salinity_mean`    → ensemble‑mean salinity (only meaningful for **001‑031**)

> For **001‑030**, `temperature_mean`/`salinity_mean` are **aliases of** `temperature`/`salinity` (since it’s a single model); this lets client code request `_mean` uniformly without branching.

---

## 4) Dataset ids the package fetches under the hood

### 001‑030 (GLORYS12V1, single‑model)

- **Daily**: `cmems_mod_glo_phy_my_0.083deg_P1D-m`
- **Monthly**: `cmems_mod_glo_phy_my_0.083deg_P1M-m`
- **Interim extension**: `cmems_mod_glo_phy_myint_0.083deg_P1D-m`, `..._P1M-m`

### 001‑031 (GREP ensemble)

- **Per‑model & per‑day/month**: `cmems_mod_glo_phy_all_my_0.25deg_P1D-m`, `..._P1M-m`
- **Ensemble mean & std**: `cmems_mod_glo_phy_mnstd_my_0.25deg_P1D-m`, `..._P1M-m`

---

## 5) Variable name mapping (CF/netCDF → package)

| Package id         | 001‑030 CF name   | 001‑031 CF name (ensemble)                                                                   |
| ------------------ | ----------------- | -------------------------------------------------------------------------------------------- |
| `temperature`      | `thetao`          | `sea_water_potential_temperature` (per‑model variables), or ensemble fields as `thetao_mean` |
| `salinity`         | `so`              | `sea_water_salinity` (per‑model variables), or ensemble fields as `so_mean`                  |
| `temperature_mean` | alias of `thetao` | `thetao_mean`                                                                                |
| `salinity_mean`    | alias of `so`     | `so_mean`                                                                                    |

> Note: exact variable naming in GREP follows CMEMS conventions (per‑model fields plus `*_mean` and `*_std`). The package resolves the right names automatically; you only need the package ids above.

---

## 6) Notes & edge cases

- **Depth axis:** both sources are full‑depth (surface→\~5900 m) on standard z‑levels.
- **Calendars & units:** time is CF‑compliant; temperature in °C, salinity in practical salinity units.
- **Missing values & scale/offset:** files use packed short ints with `scale_factor`/`add_offset`; the package auto‑decodes to float.
- **License:** CMEMS public data; cite the specific product id in publications.

---

## 7) Quick decision guide

- Need **eddies / coastal detail** → **Use 001‑030**.
- Need **ensemble mean & uncertainty** → **Use 001‑031**.
- Need **both** → consider 001‑031 for the background mean and 001‑030 for fine‑scale analysis.

