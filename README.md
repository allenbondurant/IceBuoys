# IceBuoys

An expandable R Shiny dashboard for student river-ice monitoring. **Dot Lake** is the first site, using LI-COR Cloud observations from Onset R2x100 logger **22188604**, an accumulated freezing-degree-day ice calculation, and SpyPoint imagery.

## What the dashboard shows

- Downloads LI-COR observations with a private bearer token.
- Stores tidy, deduplicated observations in `data/licor_observations.csv`.
- Updates the data automatically through GitHub Actions.
- Displays calculated ice thickness using a fixed α of 3.5 beside the latest SpyPoint photograph.
- Calculates a daily mean for each ice-surface sensor and then averages the two sensors equally.
- Plots all three hourly temperature channels with calculated daily ice thickness on a secondary axis.
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

Create a repository secret named `LICOR_API_TOKEN`. The included workflow runs every three hours and can also be run manually. It requests only logger `22188604`, merges new observations with the existing CSV, removes duplicates, and commits changes only when the data have changed.

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

Add one row to `data/sites.csv` with a unique site ID, display name, LI-COR logger serial number, timezone, and optional default model start date. Then:

1. Add the site's sensor mappings to `data/sensor_config.csv`.
2. Add its logger serial number to `LICOR_LOGGER_SN` in the workflow, comma-separated from the existing serial number.
3. Include the same `site_id` in ice measurements and the camera manifest.

No app code needs to be duplicated for another site.

## SpyPoint imagery

The existing SpyPoint downloader can remain responsible for retrieving photographs. Run the included synchronization step afterward:

```text
python scripts/sync_spypoint_folder.py "C:/Users/Allen/Documents/SpypointDownloads/CAMERA_FOLDER" --site-id dot-lake
```

The script retains the newest 60 images by default, resizes them, removes EXIF metadata, converts embedded Alaska-local camera times to UTC, and writes `data/camera_manifest.csv`. When the image files are hosted in GitHub, set `CAMERA_RAW_BASE_URL` before running the script so the manifest contains public raw-image URLs.

For the Dot Lake Windows computer, `scripts/update_dot_lake_camera.ps1` performs the complete camera update: it synchronizes the newest 12 images from the configured SpyPoint folder, commits the image and manifest changes, integrates any intervening LI-COR data commit, and pushes to GitHub. Add it as a second action in the existing SpyPoint Task Scheduler task so it runs after the downloader finishes.
