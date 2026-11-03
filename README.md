# IceBuoys

An expandable R Shiny dashboard for student river-ice monitoring. The dashboard combines LI-COR Cloud observations, an accumulated freezing-degree-day ice calculation, and SpyPoint imagery archived in Cloudflare R2. Users choose the monitoring site from the header.

## What the dashboard shows

- Downloads LI-COR observations with a private bearer token.
- Stores tidy, deduplicated observations in `data/licor_observations.csv`.
- Updates the data automatically through GitHub Actions.
- Switches the complete dashboard between configured monitoring sites.
- Displays calculated ice thickness using a fixed α of 3.5 beside the latest SpyPoint photograph.
- Calculates a daily mean for each configured ice-surface sensor and then averages those sensors equally.
- Plots each site's configured temperature channels with calculated daily ice thickness on a secondary axis.
- Starts each displayed ice season on September 1.
- Keeps sensor mappings and future-site configuration out of the public interface.

## Model

The first classroom model is:

```text
h = alpha * sqrt(FDD)
```

where `h` is thickness in centimeters, `alpha` is fixed at 3.5, and `FDD` is accumulated freezing degree days in °C·days. For each day, the app first calculates the daily mean for surface sensors `22585844-1` and `22585845-1`, gives the two sensor means equal weight, and accumulates values below 0 °C beginning September 1.

## Local setup

1. Install R and run `Rscript install_packages.R`.
2. Install the Python dependencies with `python -m pip install -r requirements.txt`.
3. Copy `.Renviron.example` to `.Renviron` and place the LI-COR token there. Never commit `.Renviron`.
4. Run `python scripts/fetch_licor.py`.
5. Start the app with `shiny::runApp()` from this folder.

If no live observations exist, the app displays clearly labeled demonstration sensor and ice-measurement data.

## LI-COR data update on GitHub

Create a repository secret named `LICOR_API_TOKEN`. The included workflow runs every three hours and can also be run manually. `LICOR_LOGGER_SN` accepts one serial number or a comma-separated list. The updater fetches each logger separately, merges observations into the existing CSV, removes duplicates, and commits only when the data have changed.

The application reads `data/licor_observations.csv` directly from the public IceBuoys GitHub repository and checks it every five minutes. `OBSERVATIONS_CSV_URL` can still override that address for testing or a future repository move.

## Dot Lake sensor inventory

The first authenticated LI-COR download identified these channels:

- `22578302-1`: sensor depth
- `22578302-2`: differential pressure
- `22578302-3`: bed water temperature from the depth pressure transducer
- `22578302-4`: barometric pressure
- `22585844-1`: ice-surface temperature sensor A
- `22585845-1`: ice-surface temperature sensor B
- Battery channels for the depth PT, both temperature loggers, and the station

Both independent temperature sensors are installed at the ice surface. Their equally weighted daily average drives the calculated ice thickness.

## Planned student measurements

Measured ice-thickness points will be added as a separate data layer, most likely read from the Google spreadsheet used to collect student field measurements. These points will be overlaid on the combined graph without changing the existing sensor and camera pipelines.

## Adding another IceBuoys site

Add one row to `data/sites.csv` with a unique site ID, display name, LI-COR logger serial number, timezone, optional default model start date, and FieldCam camera slug. Then:

1. Add the site's sensor mappings to `data/sensor_config.csv`.
2. Add its logger serial number to `LICOR_LOGGER_SN` in the workflow, comma-separated from the existing serial number.
3. Add the SpyPoint camera ID to the `icebuoys` project in the FieldCam Cloud camera registry, using a camera name that produces the same slug as `camera_slug`.

No app code needs to be duplicated for another site.

## SpyPoint imagery

The Shiny app reads each site's `featured` image directly from its public FieldCam Cloud R2 manifest. The default base URL is the pilot's `r2.dev` address and can be overridden with `FIELD_CAM_BASE_URL` when a custom domain is introduced.

The legacy Windows downloader, GitHub camera manifest, and repository image copies are no longer inputs to the Shiny display. They are intentionally left intact during the cutover and can be retired separately after the R2-backed app has been verified.
