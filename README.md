# IceBuoys

An expandable R Shiny dashboard for student river-ice monitoring. **Dot Lake** is the first site, using LI-COR Cloud observations from Onset R2x100 logger **22188604**, student ice-thickness measurements, a simple Stefan freezing-degree-day model, and SpyPoint imagery.

## What the first version does

- Downloads LI-COR observations with a private bearer token.
- Stores tidy, deduplicated observations in `data/licor_observations.csv`.
- Updates the data automatically through GitHub Actions.
- Lets students change the ice-growth coefficient α from 0.50 to 3.00.
- Overlays measured ice thickness on the modeled curve.
- Reveals a least-squares best-fit α only when requested.
- Displays all logger channels without assuming the final names of the two unknown temperature sensors.
- Displays a latest camera image and recent-image gallery from `data/camera_manifest.csv`.
- Uses a site selector and configuration table so future IceBuoys locations can share one app.

## Model

The first classroom model is:

```text
h = alpha * sqrt(FDD)
```

where `h` is thickness in centimeters and `FDD` is accumulated freezing degree days in °C·days. The temperature channel and accumulation start date are selected in the app.

## Local setup

1. Install R and run `Rscript install_packages.R`.
2. Install the Python dependencies with `python -m pip install -r requirements.txt`.
3. Copy `.Renviron.example` to `.Renviron` and place the LI-COR token there. Never commit `.Renviron`.
4. Run `python scripts/fetch_licor.py`.
5. Start the app with `shiny::runApp()` from this folder.

If no live observations exist, the app displays clearly labeled demonstration sensor and ice-measurement data.

## LI-COR data update on GitHub

Create a repository secret named `LICOR_API_TOKEN`. The included workflow runs every three hours and can also be run manually. It requests only logger `22188604`, merges new observations with the existing CSV, removes duplicates, and commits changes only when the data have changed.

For a deployed Shiny app, set `OBSERVATIONS_CSV_URL` to the raw GitHub URL for `data/licor_observations.csv`. The application checks it every five minutes.

## Dot Lake sensor inventory

The first authenticated LI-COR download identified these channels:

- `22578302-1`: sensor depth
- `22578302-2`: differential pressure
- `22578302-3`: bed temperature from the depth pressure transducer
- `22578302-4`: barometric pressure
- `22585844-1`: temperature probe A
- `22585845-1`: temperature probe B
- Battery channels for the depth PT, both temperature loggers, and the station

Chris still needs to confirm which independent temperature probe is at the water surface and which is at the other depth. Until then, the app displays their serial numbers and lets the user choose either probe as the model-driving temperature. The app also discovers future unconfigured channels automatically, so an incomplete configuration does not prevent plotting.

## Adding another IceBuoys site

Add one row to `data/sites.csv` with a unique site ID, display name, LI-COR logger serial number, timezone, and optional default model start date. Then:

1. Add the site's sensor mappings to `data/sensor_config.csv`.
2. Add its logger serial number to `LICOR_LOGGER_SN` in the workflow, comma-separated from the existing serial number.
3. Include the same `site_id` in ice measurements and the camera manifest.

No app code needs to be duplicated for another site.

## Student measurements

Add measurements to `data/ice_measurements.csv`:

```csv
site_id,date,thickness_cm,team,note
dot-lake,2026-11-03,12.4,Team A,Near centerline
```

Students can also upload a CSV with `date` and `thickness_cm` columns during a session. Uploaded files are temporary and do not overwrite the project data.

## SpyPoint imagery

The existing SpyPoint downloader can remain responsible for retrieving photographs. Run the included synchronization step afterward:

```text
python scripts/sync_spypoint_folder.py "C:/Users/Allen/Documents/SpypointDownloads/CAMERA_FOLDER" --site-id dot-lake
```

The script retains the newest 60 images by default, resizes them, removes EXIF metadata, converts embedded Alaska-local camera times to UTC, and writes `data/camera_manifest.csv`. When the image files are hosted in GitHub, set `CAMERA_RAW_BASE_URL` before running the script so the manifest contains public raw-image URLs.

## Important next check

The first authenticated LI-COR response will tell us the exact `sensor_sn`, `sensor_measurement_type`, units, and data-type values. Review those fields before treating the model-driving temperature as physically equivalent to air temperature.
