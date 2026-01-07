# Load required libraries
required_packages <- c(
  "ggplot2", "dplyr", "readxl", "tidyr", "lubridate", "tidyverse", "writexl", "AER", "mgcv","terra", "sf", "viridis", "tidyterra", "patchwork", "cowplot", "grid", "rsvg", "ggpubr", "ggridges", "irr", "ggspatial", "purrr", "ggthemes", "ggrepel", "arcgis", "elevatr", "rayshader", "leaflet", "randomForest", "mgcv", "htmltools", "htmlwidgets"
)

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}
theme_set(theme_pubr())

# Get the project root directory from this script's location
# This works whether you run from RStudio, source the script, or run interactively
if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  # Running in RStudio
  script_dir <- dirname(rstudioapi::getSourceEditorContext()$path)
  project_root <- dirname(script_dir)
} else {
  # Running from command line - use current working directory
  project_root <- getwd()
}

# Load the data using path relative to project root
index_raw <- read.csv(file.path(project_root, "raw_data", "Pacific_herring_spawn_index_data_2025_EN.csv"))

# ========================================
# DATA PREPARATION
# ========================================

# Convert dates and filter to last 10 years
spawn_data <- index_raw %>%
as.data.frame(.)%>%
  mutate(
    StartDate = as.Date(StartDate),
    StartDOY=yday(StartDate),
    EndDate = as.Date(EndDate),
    Year = as.numeric(Year),
    # Clean numeric columns
    Longitude = as.numeric(Longitude),
    Latitude = as.numeric(Latitude),
    Length = as.numeric(Length),
    Width = as.numeric(Width),
    Surface = as.numeric(Surface)
  ) %>%
  filter(Year >= 2016, Year <= 2025) %>%  # Last 10 years (data up to 2025)
  filter(!is.na(Latitude), !is.na(Longitude), !is.na(StartDate))%>%
  mutate(index = replace_na(Understory, 0) + replace_na(Macrocystis, 0) + replace_na(Surface, 0))

# Identify locations with at least some recorded biomass
# Filter out locations that only have 0 index (unsurveyed but spawn known to occur)
locations_with_data <- spawn_data %>%
  group_by(LocationCode) %>%
  filter(any(index > 0)) %>%  # Keep locations with at least one non-zero index
  ungroup()

# Aggregate by location to get historical patterns
location_summary <- locations_with_data %>%
  group_by(LocationCode, LocationName, Latitude, Longitude) %>%
  summarise(
    # Count metrics
    n_total_events = n(),  # Total recorded events
    n_measured_events = sum(index > 0),  # Events with biomass data
    n_years_observed = n_distinct(Year),
    
    # Biomass metrics (only from events with data)
    avg_index = mean(index[index > 0], na.rm = TRUE),
    sd_index = sd(index[index > 0], na.rm = TRUE),
    sd_log_index = sd(log(index[index > 0] + 1), na.rm = TRUE),  # SD on log scale
    max_index = max(index, na.rm = TRUE),
    median_index = median(index[index > 0], na.rm = TRUE),
    
    # Timing metrics
    avg_start_doy = mean(StartDOY, na.rm = TRUE),
    sd_start_doy = sd(StartDOY, na.rm = TRUE),
    earliest_doy = min(StartDOY, na.rm = TRUE),
    latest_doy = max(StartDOY, na.rm = TRUE),
    
    # Recency
    most_recent_year = max(Year, na.rm = TRUE),
    years_since_spawn = 2025 - max(Year, na.rm = TRUE),
    
    .groups = 'drop'
  ) %>%
  filter(n_measured_events >= 2)  # Only locations with at least 2 measured spawns

# ========================================
# PREDICTIVE MODELS
# ========================================

# Model 1: Predict spawn timing (day of year) based on location
timing_model_data <- locations_with_data %>%
  filter(!is.na(StartDOY)) %>%
  group_by(LocationCode) %>%
  filter(n() >= 3) %>%  # Need at least 3 observations
  ungroup()

if(nrow(timing_model_data) > 0) {
  # GAM for spawn timing with prediction intervals
  timing_model <- gam(StartDOY ~ s(Latitude) + s(Longitude) + s(Year), 
                      data = timing_model_data)
}

# Model 2: Predict spawn magnitude (index biomass)
magnitude_model_data <- locations_with_data %>%
  filter(index > 0) %>%  # Only measured spawns
  mutate(log_index = log(index + 1))  # Log transform for better modeling

if(nrow(magnitude_model_data) > 0) {
  # GAM for spawn magnitude
  magnitude_model <- gam(log_index ~ s(Latitude) + s(Longitude) + s(StartDOY), 
                        data = magnitude_model_data)
}

# ========================================
# PREDICTIONS FOR 2026
# ========================================

# Predict for all historical locations with data
predictions_2026 <- location_summary %>%
  mutate(
    Year = 2026,
    
    # TIMING PREDICTIONS - Use historical average for transparency
    predicted_doy = avg_start_doy,
    
    # Calculate timing variability (95% prediction interval)
    timing_lower_95 = pmax(1, predicted_doy - 1.96 * sd_start_doy),
    timing_upper_95 = pmin(365, predicted_doy + 1.96 * sd_start_doy),
    
    # MAGNITUDE PREDICTIONS - Use historical average for transparency
    predicted_index = avg_index,
    
    # Calculate magnitude variability (95% prediction interval)
    # Using standard deviation on log scale for better intervals
    sd_log_index_adj = ifelse(is.na(sd_log_index) | sd_log_index == 0, 
                              0.5,  # Default if no variability
                              sd_log_index),
    magnitude_lower_95 = pmax(0, avg_index - 1.96 * sd_index),
    magnitude_upper_95 = avg_index + 1.96 * sd_index,
    
    # SPAWN PROBABILITY 
    # Based on frequency, recency, and consistency
    freq_score = n_measured_events / 10,  # Frequency over 10 years
    recency_score = case_when(
      years_since_spawn == 0 ~ 1.0,      # Spawned in 2025
      years_since_spawn == 1 ~ 0.8,      # Spawned in 2024
      years_since_spawn == 2 ~ 0.5,      # Spawned in 2023
      years_since_spawn <= 5 ~ 0.4,      # Spawned 2020-2022
      TRUE ~ 0.2                          # Older than 5 years
    ),
    consistency_score = 1 - (sd_index / (avg_index + 1)),  # Higher score for consistent spawns
    spawn_probability = pmin(1, freq_score * 0.5 + recency_score * 0.3 + consistency_score * 0.2),
    predicted_date = as.Date(predicted_doy - 1, origin = "2026-01-01"),
    predicted_date_lower = as.Date(timing_lower_95 - 1, origin = "2026-01-01"),
    predicted_date_upper = as.Date(timing_upper_95 - 1, origin = "2026-01-01")
  )

# ========================================
# INTERACTIVE MAP
# ========================================

# Create color palettes
prob_pal <- colorNumeric(palette = "YlOrRd", domain = predictions_2026$spawn_probability)
mag_pal <- colorNumeric(palette = "Blues", domain = predictions_2026$predicted_index)

# Create interactive leaflet map
spawn_map <- leaflet(predictions_2026) %>%
  addProviderTiles(providers$Esri.OceanBasemap) %>%
  
  # Add circle markers sized by predicted magnitude, colored by probability
  addCircleMarkers(
    lng = ~Longitude,
    lat = ~Latitude,
    radius = ~sqrt(predicted_index) / 5,  # Scale radius by predicted biomass
    color = ~prob_pal(spawn_probability),
    fillColor = ~prob_pal(spawn_probability),
    fillOpacity = 0.7,
    stroke = TRUE,
    weight = 2,
    popup = ~paste0(
      "<b>", LocationName, "</b><br/>",
      "Location Code: ", LocationCode, "<br/><br/>",
      
      "<b>2026 Predictions:</b><br/>",
      "Spawn Probability: <b>", round(spawn_probability * 100, 1), "%</b><br/>",
      "Predicted Date: <b>", format(predicted_date, "%B %d"), "</b><br/>",
      "  (95% CI: ", format(predicted_date_lower, "%b %d"), " - ", 
                     format(predicted_date_upper, "%b %d"), ")<br/>",
      "Predicted Biomass: <b>", round(predicted_index, 1), "</b> tons<br/>",
      "  (95% CI: ", round(magnitude_lower_95, 1), " - ", 
                     round(magnitude_upper_95, 1), " tons)<br/><br/>",
      
      "<b>Historical Data (2016-2025):</b><br/>",
      "Measured Spawns: ", n_measured_events, " events<br/>",
      "Avg Biomass: ", round(avg_index, 1), " tons<br/>",
      "Max Biomass: ", round(max_index, 1), " tons<br/>",
      "Avg Date: Day ", round(avg_start_doy), " (± ", round(sd_start_doy, 1), " days)<br/>",
      "Last Spawn: ", most_recent_year
    ),
    label = ~paste0(LocationName, " (", round(spawn_probability * 100), "% probability)")
  ) %>%
  
  # Add legend for probability
  addLegend(
    position = "bottomright",
    pal = prob_pal,
    values = ~spawn_probability,
    title = "Spawn Probability<br/>2026",
    labFormat = labelFormat(suffix = "%", transform = function(x) x * 100)
  ) %>%
  
  # Add scale bar
  addScaleBar(position = "bottomleft")

# Print the map
print(spawn_map)

# Create enhanced page with header (will be saved below after docs_dir is created)
full_page <- tagList(
  tags$div(
    style = "text-align: center; padding: 20px; background-color: #2c5f7d; color: white; font-family: Arial, sans-serif;",
    tags$h1(style = "margin-bottom: 10px; font-size: 2em;", "Pacific Herring Spawn Predictions 2026"),
    tags$p(style = "font-size: 1.1em; margin: 10px auto; max-width: 800px;", 
           "This interactive map predicts Pacific herring spawning locations and timing for 2026 based on 10 years of historical data (2016-2025) from Fisheries and Oceans Canada."),
    tags$p(style = "margin: 5px; font-size: 0.95em;",
           tags$strong("How to use:"), " Click on any circle to see detailed predictions. Circle size = predicted biomass. Circle color = spawn probability (yellow = low, red = high).")
  ),
  spawn_map,
  tags$div(
    style = "text-align: center; padding: 15px; background-color: #f0f0f0; border-top: 2px solid #2c5f7d;",
    tags$p(style = "margin: 5px; font-size: 0.9em;",
      tags$strong("Data Source:"), " DFO Pacific Herring Spawn Index | ",
      tags$strong("Analysis Period:"), " 2016-2025 | ",
      tags$strong("Predictions:"), " Historical averages with 95% confidence intervals"
    ),
    tags$p(style = "margin: 10px;",
      tags$a(href = "https://github.com/JTDingwall/herringspawnprediction", 
             style = "color: #2c5f7d; font-weight: bold; text-decoration: none; font-size: 1em;",
             "📊 View Methodology & Code on GitHub")
    )
  )
)
# Save map as HTML for GitHub Pages
library(htmlwidgets)
# Create docs folder if it doesn't exist
docs_dir <- file.path(project_root, "docs")
if (!dir.exists(docs_dir)) {
  dir.create(docs_dir)
}

# Save enhanced page with dependencies in separate folder (works better with GitHub Pages)
htmlwidgets::saveWidget(
  full_page, 
  file.path(docs_dir, "index.html"),
  selfcontained = FALSE,
  title = "Pacific Herring Spawn Predictions 2026"
)
cat("\nMap saved to:", file.path(docs_dir, "index.html"), "\n")


# Fix potential encoding issues that cause Quirks Mode
index_path <- file.path(docs_dir, "index.html")

# Read the file and ensure proper encoding
html_content <- readLines(index_path, warn = FALSE, encoding = "UTF-8")

# Write back with UTF-8 encoding (no BOM)
writeLines(html_content, index_path, useBytes = FALSE)

cat("\nMap saved to:", index_path, "\n")