library(shiny)
library(bslib)
library(dplyr)
library(readr)
library(ggplot2)
library(lubridate)
library(scales)

# Backend configuration
DEFAULT_SITE_ID <- Sys.getenv("DEFAULT_SITE_ID", "dot-lake")
OBSERVATIONS_URL <- Sys.getenv("OBSERVATIONS_CSV_URL", "")
CAMERA_MANIFEST_URL <- Sys.getenv("CAMERA_MANIFEST_URL", "")
MODEL_SENSOR_SN <- Sys.getenv("MODEL_SENSOR_SN", "22585844-1") # Probe A
DEFAULT_ALPHA <- as.numeric(Sys.getenv("DEFAULT_ALPHA", "1.50"))

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

# One-page public dashboard
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
      .dashboard-card { background: white; border-radius: 13px; padding: 18px 20px;
                        box-shadow: 0 3px 15px rgba(23,50,77,.08); margin-bottom: 18px; }
      .dashboard-card h2 { font-size: 1.25rem; margin: 0 0 12px 0; font-weight: 720; }
      .value-row { display: flex; flex-wrap: wrap; gap: 10px; margin: 0 0 8px 0; }
      .value-pill { background: #edf6f8; border-radius: 10px; padding: 8px 12px; min-width: 150px; }
      .value-label { color: #62798a; font-size: .76rem; text-transform: uppercase;
                     letter-spacing: .035em; }
      .value-number { font-size: 1.18rem; font-weight: 720; color: #17324d; }
      .lower-grid { display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(360px, .85fr);
                    gap: 18px; align-items: start; }
      .lower-grid .dashboard-card { margin-bottom: 0; }
      .alpha-wrap { background: #edf6f8; border-radius: 10px; padding: 12px 15px 5px 15px;
                    margin-bottom: 8px; }
      .alpha-note { color: #62798a; font-size: .84rem; margin-top: -5px; }
      .ice-result { color: #17324d; font-size: 1.55rem; font-weight: 760; margin-bottom: 5px; }
      .camera-main { display: block; width: 100%; max-height: 515px; object-fit: contain;
                     background: #e5ecef; border-radius: 9px; }
      .camera-caption { color: #62798a; font-size: .86rem; margin: 9px 1px 0 1px; }
      .demo-banner { background: #fff4ce; color: #654f00; border-radius: 9px;
                     padding: 9px 13px; margin-bottom: 16px; }
      .shiny-input-container { width: 100%; }
      @media (max-width: 900px) {
        .lower-grid { grid-template-columns: 1fr; }
        .hero-row { align-items: flex-start; flex-direction: column; }
        .updated { text-align: left; }
      }
      @media (max-width: 560px) {
        .container-fluid { padding: 0 12px 24px 12px; }
        .hero { margin-left: -12px; margin-right: -12px; padding: 18px; }
        .value-pill { flex: 1 1 100%; }
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
    class = "dashboard-card",
    h2("Water temperatures"),
    uiOutput("temperature_values"),
    plotOutput("temperature_plot", height = "330px")
  ),
  div(
    class = "dashboard-card",
    h2("Water depth"),
    uiOutput("depth_value"),
    plotOutput("depth_plot", height = "260px")
  ),
  div(
    class = "lower-grid",
    div(
      class = "dashboard-card",
      h2("Calculated ice thickness"),
      div(
        class = "alpha-wrap",
        sliderInput(
          "alpha",
          HTML("Ice-growth coefficient (&alpha;)"),
          min = 0.50,
          max = 3.00,
          value = DEFAULT_ALPHA,
          step = 0.05
        ),
        p(class = "alpha-note", "Move the slider and compare the estimate with ice measured at the site.")
      ),
      uiOutput("ice_result"),
      plotOutput("ice_plot", height = "330px")
    ),
    div(
      class = "dashboard-card",
      h2("Dot Lake camera"),
      uiOutput("latest_camera_image"),
      uiOutput("latest_camera_details")
    )
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
    observations() %>%
      filter(sensor_sn %in% c("22578302-3", "22585844-1", "22585845-1")) %>%
      mutate(
        local_time = with_tz(timestamp_utc, site_timezone()),
        temp_c = to_celsius(value, unit),
        channel = factor(
          display_name,
          levels = c(
            "Bed temperature (depth PT)",
            "Temperature probe A (22585844)",
            "Temperature probe B (22585845)"
          )
        )
      ) %>%
      filter(!is.na(channel))
  })

  output$temperature_values <- renderUI({
    latest <- temperature_data() %>%
      group_by(channel) %>%
      slice_max(timestamp_utc, n = 1, with_ties = FALSE) %>%
      ungroup()
    div(
      class = "value-row",
      lapply(seq_len(nrow(latest)), function(i) {
        div(
          class = "value-pill",
          div(class = "value-label", as.character(latest$channel[[i]])),
          div(class = "value-number", paste0(number(latest$temp_c[[i]], accuracy = 0.1), " °C"))
        )
      })
    )
  })

  output$temperature_plot <- renderPlot({
    validate(need(nrow(temperature_data()) > 0, "No temperature data are available."))
    ggplot(temperature_data(), aes(local_time, temp_c, color = channel)) +
      geom_hline(yintercept = 0, color = "#9aabb5", linetype = "dashed") +
      geom_line(linewidth = .85, na.rm = TRUE) +
      scale_color_manual(
        values = c("#334e68", "#168aad", "#db7c26"),
        labels = c("Bed temperature", "Probe A", "Probe B"),
        drop = FALSE
      ) +
      labs(x = NULL, y = "Temperature (°C)", color = NULL) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "top", legend.justification = "left", panel.grid.minor = element_blank())
  })

  depth_data <- reactive({
    observations() %>%
      filter(sensor_sn == "22578302-1") %>%
      mutate(local_time = with_tz(timestamp_utc, site_timezone()))
  })

  output$depth_value <- renderUI({
    latest <- tail(depth_data(), 1)
    value <- if (nrow(latest) == 0) "—" else paste0(number(latest$value, accuracy = .001), " m")
    div(
      class = "value-row",
      div(class = "value-pill", div(class = "value-label", "Latest depth"), div(class = "value-number", value))
    )
  })

  output$depth_plot <- renderPlot({
    validate(need(nrow(depth_data()) > 0, "No water-depth data are available."))
    ggplot(depth_data(), aes(local_time, value)) +
      geom_area(fill = "#83c5d6", alpha = .35) +
      geom_line(color = "#1f7898", linewidth = .9) +
      labs(x = NULL, y = "Water depth (m)") +
      theme_minimal(base_size = 12) +
      theme(panel.grid.minor = element_blank())
  })

  daily_model_temperature <- reactive({
    observations() %>%
      filter(sensor_sn == MODEL_SENSOR_SN) %>%
      mutate(
        local_time = with_tz(timestamp_utc, site_timezone()),
        date = as.Date(local_time),
        temp_c = to_celsius(value, unit)
      ) %>%
      group_by(date) %>%
      summarise(temp_c = mean(temp_c, na.rm = TRUE), .groups = "drop") %>%
      arrange(date)
  })

  model_start_date <- reactive({
    configured <- active_site()$default_model_start[[1]]
    environment <- Sys.getenv("MODEL_START_DATE", "")
    requested <- if (!is.na(configured) && nzchar(configured)) configured else environment
    if (nzchar(requested)) as.Date(requested) else min(daily_model_temperature()$date)
  })

  model_data <- reactive({
    req(input$alpha)
    validate(need(nrow(daily_model_temperature()) > 0, "Probe A data are unavailable."))
    daily_model_temperature() %>%
      mutate(
        daily_fdd = if_else(date >= model_start_date(), pmax(0, -temp_c), 0),
        cumulative_fdd = cumsum(daily_fdd),
        modeled_thickness_cm = input$alpha * sqrt(cumulative_fdd)
      )
  })

  output$ice_result <- renderUI({
    current <- tail(model_data(), 1)
    tagList(
      div(
        class = "ice-result",
        paste0(number(current$modeled_thickness_cm, accuracy = .1), " cm calculated thickness")
      ),
      p(
        class = "alpha-note",
        "Based on Probe A and ",
        number(current$cumulative_fdd, accuracy = .1),
        " accumulated freezing degree days."
      )
    )
  })

  output$ice_plot <- renderPlot({
    ggplot(model_data(), aes(date, modeled_thickness_cm)) +
      geom_area(fill = "#a8dadc", alpha = .55) +
      geom_line(color = "#287271", linewidth = 1.05) +
      labs(x = NULL, y = "Calculated ice thickness (cm)") +
      scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, .08))) +
      theme_minimal(base_size = 12) +
      theme(panel.grid.minor = element_blank())
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
      tags$img(src = manifest$image_url[[1]], class = "camera-main", alt = "Latest Dot Lake camera image")
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
      if (!is.na(latest$caption[[1]]) && nzchar(latest$caption[[1]]))
        tagList(br(), latest$caption[[1]])
    )
  })
}

shinyApp(ui, server)
