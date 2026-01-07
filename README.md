# Pacific Herring Spawn Prediction for 2026

This map predicts the timing, location, and magnitude of Pacific herring spawning events for 2026 based on historical data from 2016-2025. The prediction is made **solely** using the previous years of spawning index assessments. As such, it is a simple estimate and does not consider changes in population, spawning habitat quality, climate change, etc. The analysis produces an interactive map showing spawn probability, predicted dates, and expected biomass at historical spawning locations.

## Data Source

**Dataset**: Pacific Herring Spawn Index Data (2025 spawn Edition)  
**Source**: Fisheries and Oceans Canada (DFO)  
**Temporal Coverage**: 1951-2025  
**Analysis Period**: 2016-2025 (last 10 years)

The dataset includes:
- Geographic coordinates (latitude/longitude)
- Spawn timing (start/end dates)
- Biomass estimates (Surface, Macrocystis, Understory indices)
- Location metadata (codes, names, statistical areas)

## Interactive Map
[![Map Preview](raw_data/map_screenshot.png)](https://jtdingwall.github.io/herringspawnprediction/)

***Click the image above to view the interactive map.***

Clicking on a spawning point will provide the estimated date of spawn.



## Data Processing Decisions

### 1. Biomass Index Calculation

**Decision**: Combined three biomass components into a single index
```r
index = Understory + Macrocystis + Surface
```

**Rationale**: 
- Provides a comprehensive measure of total spawn biomass
- Some events have NA values for individual components (unsurveyed)
- NA values treated as 0 using `replace_na()` to avoid losing valid data

### 2. Location Filtering

**Decision**: Only analyze locations with at least 2 measured spawning events (index > 0)

**Rationale**:
- Some locations have recorded spawns but zero biomass (spawn known to occur but not surveyed)
- Predictions require actual biomass measurements, not just presence/absence
- Ensures predictions are based on core spawns, not one offs

**Implementation**:
```r
locations_with_data <- spawn_data %>%
  group_by(LocationCode) %>%
  filter(any(index > 0)) %>%  # At least one non-zero measurement
  ungroup()
```

### 3. Temporal Scope

**Decision**: Use 2016-2025 data (10-year window)

**Rationale**:
- Recent data more relevant for current predictions
- Balances between sufficient sample size and temporal relevance
- Captures recent environmental/behavioural trends


## Prediction Methodology

### Timing Predictions

**Method**: Historical average DOY ± 95% confidence intervals

**Formula**:
- Predicted date = Average DOY across 2016-2025
- 95% CI = Predicted DOY ± 1.96 × Standard Deviation

**Example**: 
- Cape Lazo: Average DOY = 68 (March 9)
- SD = 7 days
- 95% CI: Day 54-82 (Feb 23 - Mar 23)

### Biomass Predictions

**Method**: Historical average biomass index ± 95% confidence intervals

**Formula**:
- Predicted biomass = Average index (excluding zeros)
- 95% CI = Average ± 1.96 × Standard Deviation

**Rationale**:
- Only measured spawns used (index > 0)
- Reflects typical spawn magnitude at each location
- Variability bounds indicate uncertainty

### Spawn Probability

**Method**: Composite score based on three factors

**Formula**:
```r
spawn_probability = (frequency_score × 0.5) + 
                    (recency_score × 0.3) + 
                    (consistency_score × 0.2)
```

**Components**:

1. **Frequency Score (50% weight)**: 
   - Number of measured events / 10 years
   - Captures how often spawning occurs

2. **Recency Score (30% weight)**:
   - 2025 spawn = 1.0
   - 2024 spawn = 0.8
   - 2023 spawn = 0.5
   - 2020-2022 = 0.4
   - Pre-2020 = 0.2
   - Recent spawns increase probability

3. **Consistency Score (20% weight)**:
   - Measured events / years observed
   - High consistency = spawns whenever checked
   - Low consistency = intermittent spawning

**Rationale**:
- Frequency is most important (largest weight)
- Recent activity indicates ongoing suitability
- Consistency shows reliability
- Weights based on ecological understanding of herring behavior

## Summary Metrics

### Location-Level Metrics

For each location, we calculate:

- `n_total_events`: All recorded spawns (2016-2025)
- `n_measured_events`: Spawns with biomass data (index > 0)
- `n_years_observed`: Number of distinct years with observations
- `avg_index`: Mean biomass from measured spawns
- `sd_index`: Standard deviation of biomass
- `max_index`: Maximum recorded biomass
- `avg_start_doy`: Average spawn timing (day of year)
- `sd_start_doy`: Variability in spawn timing
- `most_recent_year`: Last year of spawning
- `years_since_spawn`: Years since last spawn

### Prediction Outputs

For 2026, each location receives:

- **Spawn probability**: 0-100% likelihood of spawning
- **Predicted date**: Expected start date with 95% CI
- **Predicted biomass**: Expected index with 95% CI
- **Historical context**: Past events, averages, maxima

## Interactive Map Features

The Leaflet map displays:

- **Circle size**: Proportional to predicted biomass (sqrt transformation for visual clarity)
- **Circle color**: Spawn probability (yellow = low, red = high)
- **Popups**: Detailed predictions and historical data
- **Labels**: Location names with probability on hover
- **Basemap**: Esri Ocean Basemap for geographic context

## Data Quality Considerations

### Assumptions
- Historical patterns reflect future conditions
- No major environmental regime shifts
- Survey methodology consistent across years

### Limitations
- Does not account for fish population dynamics
- Assumes spawn probability independent across locations
- Limited to locations with historical measurements

## Author

Developed by Jake Dingwall

## Data Citation
Fisheries and Oceans Canada (DFO). (2026). Pacific Herring Spawn Index Data [Data set]. https://open.canada.ca/data/en/dataset/d892511c-d851-4f85-a0ec-708bc05d2810

## License

This project is intended for research and educational purposes. Please cite appropriately if used in publications or reports.

---

**Last Updated**: January 2026  
**Analysis Period**: 2016-2025  
**Prediction Year**: 2026
