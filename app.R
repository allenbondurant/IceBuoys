library(shiny)
library(bslib)
library(dplyr)
library(readr)
library(ggplot2)
library(lubridate)
library(scales)

# Backend configuration
DEFAULT_SITE_ID <- Sys.getenv("DEFAULT_SITE_ID", "dot-lake")
MODEL_ALPHA <- 3.5
SURFACE_SENSOR_SNS <- c("22585844-1", "22585845-1")
TEMPERATURE_SENSOR_SNS <- c("22578302-3", SURFACE_SENSOR_SNS)

OBSERVATIONS_URL <- Sys.getenv(
  "OBSERVATIONS_CSV_URL",
  "https://raw.githubusercontent.com/allenbondurant/IceBuoys/main/data/licor_observations.csv"
)
CAMERA_MANIFEST_URL <- Sys.getenv(
  "CAMERA_MANIFEST_URL",
  "https://raw.githubusercontent.com/allenbondurant/IceBuoys/main/data/camera_manifest.csv"
)

site_config <- suppressMessages(
  readr::read_csv(
    "data/sites.csv",
    show_col_types = FALSE,
    col_types = cols(.default = col_character())
  )
)

sensor_config <- suppressMessages(
  readr::read_csv("data/sensor_config.csv", show_col_types = FALSE)
)

read_csv_source <- function(remote_url, local_path, cache_bust = TRUE) {
  source <- local_path
  if (nzchar(remote_url)) {
    separator <- if (grepl("?", remote_url, fixed = TRUE)) "&" else "?"
    source <- if (cache_bust) {
      paste0(remote_url, separator, "refresh=", floor(as.numeric(Sys.time()) / 300))
    } else {
      remote_url
    }
  }

  suppressMessages(
    readr::read_csv(source, show_col_types = FALSE, na = c("", "NA", "null"))
  )
}

standardize_observations <- function(data) {
  required <- c(
    "logger_sn", "sensor_sn", "timestamp_utc", "data_type",
    "data_type_id", "value", "unit", "sensor_measurement_type"
  )
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop("Observation data is missing: ", paste(missing, collapse = ", "))
  }

  data %>%
    mutate(
      logger_sn = as.character(logger_sn),
      sensor_sn = as.character(sensor_sn),
      data_type_id = as.character(data_type_id),
      timestamp_utc = lubridate::ymd_hms(timestamp_utc, tz = "UTC", quiet = TRUE),
      value = as.numeric(value)
    ) %>%
    filter(!is.na(timestamp_utc), !is.na(value)) %>%
    left_join(sensor_config, by = c("sensor_sn", "sensor_measurement_type")) %>%
    mutate(
      display_name = coalesce(display_name, sensor_measurement_type),
      display_order = coalesce(display_order, 99)
    ) %>%
    arrange(timestamp_utc, display_order)
}

read_observations <- function() {
  live <- tryCatch(
    read_csv_source(OBSERVATIONS_URL, "data/licor_observations.csv"),
    error = function(e) tibble()
  )

  use_demo <- nrow(live) == 0
  data <- if (use_demo) {
    read_csv_source("", "data/demo_observations.csv", cache_bust = FALSE)
  } else {
    live
  }

  result <- standardize_observations(data)
  attr(result, "demo_data") <- use_demo
  result
}

to_celsius <- function(value, unit) {
  fahrenheit <- grepl("(^|[^a-z])f($|[^a-z])|fahrenheit", unit, ignore.case = TRUE)
  ifelse(fahrenheit, (value - 32) * 5 / 9, value)
}

theme_ice <- bslib::bs_theme(
  version = 5,
  bg = "#eef4f6",
  fg = "#17324d",
  primary = "#1f7898",
  base_font = bslib::font_google("Atkinson Hyperlegible")
)

ui <- fluidPage(
  theme = theme_ice,
  tags$head(
    tags$title("IceBuoys — Dot Lake"),
    tags$style(HTML("
      body { background: #eef4f6; }
      .container-fluid { max-width: 1380px; padding: 0 24px 32px 24px; }
      .hero { background: linear-gradient(125deg, #12324a, #1f7898); color: white;
              padding: 22px 28px; margin: 0 -24px 20px -24px; }
      .hero-row { display: flex; align-items: flex-end; justify-content: space-between; gap: 18px; }
      .hero h1 { margin: 0; font-size: 2rem; font-weight: 750; }
      .hero p { margin: 4px 0 0 0; opacity: .9; }
      .updated { text-align: right; font-size: .88rem; opacity: .88; }
      .top-grid { display: grid; grid-template-columns: minmax(320px, .8fr) minmax(440px, 1.2fr);
                  gap: 18px; align-items: stretch; margin-bottom: 18px; }
      .dashboard-card { background: white; border-radius: 13px; padding: 18px 20px;
                        box-shadow: 0 3px 15px rgba(23,50,77,.08); }
      .dashboard-card h2 { font-size: 1.25rem; margin: 0 0 12px 0; font-weight: 720; }
      .thickness-card { display: flex; flex-direction: column; min-height: 390px; }
      .thickness-center { flex: 1; display: flex; flex-direction: column;
                          justify-content: center; align-items: center; text-align: center; }
      .ice-number { color: #17324d; font-size: clamp(4rem, 9vw, 7.5rem);
                    font-weight: 780; line-height: .95; letter-spacing: -.05em; }
      .ice-unit { color: #287271; font-size: 1.25rem; font-weight: 700; margin-top: 8px; }
      .ice-method { color: #62798a; font-size: .95rem; max-width: 430px; margin: 18px auto 0 auto; }
      .ice-detail { color: #62798a; font-size: .82rem; margin-top: 8px; }
      .camera-main { display: block; width: 100%; height: 315px; object-fit: contain;
                     background: #e5ecef; border-radius: 9px; }
      .camera-caption { color: #62798a; font-size: .86rem; margin: 9px 1px 0 1px; }
      .chart-card { margin-bottom: 0; }
      .chart-subtitle { color: #62798a; font-size: .9rem; margin: -5px 0 8px 0; }
      .demo-banner { background: #fff4ce; color: #654f00; border-radius: 9px;
                     padding: 9px 13px; margin-bottom: 16px; }
      @media (max-width: 900px) {
        .top-grid { grid-template-columns: 1fr; }
        .thickness-card { min-height: 310px; }
        .hero-row { align-items: flex-start; flex-direction: column; }
        .updated { text-align: left; }
      }
      @media (max-width: 560px) {
        .container-fluid { padding: 0 12px 24px 12px; }
        .hero { margin-left: -12px; margin-right: -12px; padding: 18px; }
        .camera-main { height: 260px; }
      }
    "))
  ),
  div(
    class = "hero",
    div(
      class = "hero-row",
      div(h1("IceBuoys"), p(textOutput("site_name", inline = TRUE))),
      div(class = "updated", uiOutput("last_updated"))
    )
  ),
  uiOutput("data_mode_banner"),
  div(
    class = "top-grid",
    div(
      class = "dashboard-card thickness-card",
      h2("Calculated ice thickness"),
      uiOutput("ice_summary")
    ),
    div(
      class = "dashboard-card",
      h2("Latest site photo"),
      uiOutput("latest_camera_image"),
      uiOutput("latest_camera_details")
    )
  ),
  div(
    class = "dashboard-card chart-card",
    h2("Temperature and calculated ice thickness"),
    p(class = "chart-subtitle", "Hourly temperature observations and calculated daily ice thickness since September 1."),
    plotOutput("combined_plot", height = "560px")
  )
)

server <- function(input, output, session) {
  all_observations <- reactivePoll(
    intervalMillis = 300000,
    session = session,
    checkFunc = function() floor(as.numeric(Sys.time()) / 300),
    valueFunc = read_observations
  )

  active_site <- reactive({
    selected <- site_config %>% filter(site_id == DEFAULT_SITE_ID)
    validate(need(nrow(selected) == 1, "The default site is not configured."))
    selected
  })

  site_timezone <- reactive({
    timezone <- active_site()$timezone[[1]]
    if (is.na(timezone) || !nzchar(timezone)) "America/Anchorage" else timezone
  })

  observations <- reactive({
    all_data <- all_observations()
    selected <- all_data %>%
      filter(logger_sn == as.character(active_site()$logger_sn[[1]]))
    attr(selected, "demo_data") <- attr(all_data, "demo_data")
    validate(need(nrow(selected) > 0, "No observations are available for this site."))
    selected
  })

  season_start <- reactive({
    latest_local_date <- as.Date(
      with_tz(max(observations()$timestamp_utc, na.rm = TRUE), site_timezone())
    )
    season_year <- if (month(latest_local_date) >= 9) {
      year(latest_local_date)
    } else {
      year(latest_local_date) - 1
    }
    as.Date(sprintf("%d-09-01", season_year))
  })

  output$site_name <- renderText(active_site()$site_name[[1]])

  output$last_updated <- renderUI({
    latest <- max(observations()$timestamp_utc, na.rm = TRUE)
    local_latest <- with_tz(latest, site_timezone())
    tagList(
      div("Latest sensor reading"),
      strong(format(local_latest, "%B %d, %Y at %I:%M %p"))
    )
  })

  output$data_mode_banner <- renderUI({
    if (isTRUE(attr(observations(), "demo_data"))) {
      div(class = "demo-banner", strong("Demo data are currently displayed."))
    }
  })

  temperature_data <- reactive({
    start_time <- as.POSIXct(season_start(), tz = site_timezone())

    observations() %>%
      filter(sensor_sn %in% TEMPERATURE_SENSOR_SNS) %>%
      mutate(
        local_time = with_tz(timestamp_utc, site_timezone()),
        temp_c = to_celsius(value, unit),
        channel = case_when(
          sensor_sn == "22578302-3" ~ "Bed water temperature",
          sensor_sn == "22585844-1" ~ "Ice surface temperature A",
          sensor_sn == "22585845-1" ~ "Ice surface temperature B",
          TRUE ~ display_name
        ),
        channel = factor(
          channel,
          levels = c(
            "Bed water temperature",
            "Ice surface temperature A",
            "Ice surface temperature B"
          )
        )
      ) %>%
      filter(local_time >= start_time, !is.na(channel))
  })

  daily_surface_temperature <- reactive({
    temperature_data() %>%
      filter(sensor_sn %in% SURFACE_SENSOR_SNS) %>%
      mutate(date = as.Date(local_time)) %>%
      group_by(date, sensor_sn) %>%
      summarise(sensor_daily_mean_c = mean(temp_c, na.rm = TRUE), .groups = "drop") %>%
      group_by(date) %>%
      summarise(surface_daily_mean_c = mean(sensor_daily_mean_c, na.rm = TRUE), .groups = "drop") %>%
      arrange(date)
  })

  model_data <- reactive({
    validate(need(nrow(daily_surface_temperature()) > 0, "Surface temperature data are unavailable."))

    daily_surface_temperature() %>%
      mutate(
        daily_fdd = pmax(0, -surface_daily_mean_c),
        cumulative_fdd = cumsum(daily_fdd),
        calculated_thickness_cm = MODEL_ALPHA * sqrt(cumulative_fdd),
        plot_time = as.POSIXct(date, tz = site_timezone()) + hours(12)
      )
  })

  output$ice_summary <- renderUI({
    current <- tail(model_data(), 1)
    div(
      class = "thickness-center",
      div(class = "ice-number", number(current$calculated_thickness_cm, accuracy = 0.1)),
      div(class = "ice-unit", "centimeters"),
      p(
        class = "ice-method",
        HTML("Calculated with &alpha; = 3.5 using the daily average of both ice-surface temperature sensors.")
      ),
      div(
        class = "ice-detail",
        number(current$cumulative_fdd, accuracy = 0.1),
        " accumulated freezing degree days through ",
        format(current$date, "%B %d, %Y")
      )
    )
  })

  output$combined_plot <- renderPlot({
    temperatures <- temperature_data()
    ice <- model_data()
    validate(need(nrow(temperatures) > 0, "No temperature data are available after September 1."))

    temperature_upper <- max(temperatures$temp_c, na.rm = TRUE)
    temperature_upper <- max(5, temperature_upper)
    ice_upper <- max(ice$calculated_thickness_cm, na.rm = TRUE)
    ice_scale <- if (is.finite(ice_upper) && ice_upper > 0) {
      ice_upper / temperature_upper
    } else {
      1
    }
    ice_breaks <- if (is.finite(ice_upper) && ice_upper > 0) {
      pretty(c(0, ice_upper), n = 5)
    } else {
      0
    }
    ice_breaks <- ice_breaks[ice_breaks >= 0]
    plot_end <- max(c(temperatures$local_time, ice$plot_time), na.rm = TRUE)

    ggplot(temperatures, aes(local_time, temp_c, color = channel)) +
      geom_hline(yintercept = 0, color = "#9aabb5", linetype = "dotted", linewidth = .6) +
      geom_line(linewidth = .72, alpha = .9, na.rm = TRUE) +
      geom_line(
        data = ice,
        aes(
          x = plot_time,
          y = calculated_thickness_cm / ice_scale,
          color = "Calculated ice thickness"
        ),
        inherit.aes = FALSE,
        linewidth = 1.35,
        linetype = "longdash",
        na.rm = TRUE
      ) +
      scale_color_manual(
        values = c(
          "Bed water temperature" = "#334e68",
          "Ice surface temperature A" = "#168aad",
          "Ice surface temperature B" = "#db7c26",
          "Calculated ice thickness" = "#7b2cbf"
        ),
        breaks = c(
          "Bed water temperature",
          "Ice surface temperature A",
          "Ice surface temperature B",
          "Calculated ice thickness"
        ),
        drop = FALSE
      ) +
      scale_x_datetime(
        date_breaks = "2 weeks",
        date_labels = "%b %d",
        limits = c(
          as.POSIXct(season_start(), tz = site_timezone()),
          plot_end
        ),
        expand = expansion(mult = c(0, .01))
      ) +
      scale_y_continuous(
        name = "Temperature (°C)",
        sec.axis = sec_axis(
          ~ . * ice_scale,
          name = "Calculated ice thickness (cm)",
          breaks = ice_breaks
        )
      ) +
      labs(x = NULL, color = NULL) +
      theme_minimal(base_size = 12) +
      theme(
        legend.position = "top",
        legend.justification = "left",
        legend.box = "vertical",
        panel.grid.minor = element_blank(),
        axis.title.y.left = element_text(color = "#334e68", face = "bold"),
        axis.title.y.right = element_text(color = "#7b2cbf", face = "bold")
      )
  })

  camera_manifest <- reactivePoll(
    intervalMillis = 300000,
    session = session,
    checkFunc = function() floor(as.numeric(Sys.time()) / 300),
    valueFunc = function() {
      tryCatch(
        {
          manifest <- read_csv_source(CAMERA_MANIFEST_URL, "data/camera_manifest.csv")
          if (!"site_id" %in% names(manifest)) manifest$site_id <- DEFAULT_SITE_ID
          manifest %>%
            mutate(
              site_id = as.character(site_id),
              timestamp_utc = ymd_hms(timestamp_utc, tz = "UTC", quiet = TRUE)
            ) %>%
            arrange(desc(timestamp_utc))
        },
        error = function(e) tibble()
      )
    }
  )

  output$latest_camera_image <- renderUI({
    manifest <- camera_manifest() %>% filter(site_id == DEFAULT_SITE_ID)
    if (nrow(manifest) == 0) return(p("No camera image is available yet."))
    tags$a(
      href = manifest$image_url[[1]],
      target = "_blank",
      tags$img(
        src = manifest$image_url[[1]],
        class = "camera-main",
        alt = "Latest Dot Lake camera image"
      )
    )
  })

  output$latest_camera_details <- renderUI({
    manifest <- camera_manifest() %>% filter(site_id == DEFAULT_SITE_ID)
    if (nrow(manifest) == 0) return(NULL)
    latest <- manifest[1, ]
    local_time <- with_tz(latest$timestamp_utc, site_timezone())
    div(
      class = "camera-caption",
      strong(format(local_time, "%B %d, %Y at %I:%M %p")),
      if (!is.na(latest$caption[[1]]) && nzchar(latest$caption[[1]])) {
        tagList(br(), latest$caption[[1]])
      }
    )
  })
}

shinyApp(ui, server)
