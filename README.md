# Pacific Herring Spawn Prediction for 2026

This map predicts the timing, location, and magnitude of Pacific herring spawning events for 2026 based on historical data from 2016-2025. The analysis produces an interactive map showing spawn probability, predicted dates, and expected biomass at historical spawning locations.

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
- Minimum of 2 events needed to calculate variability metrics (standard deviation)
- Ensures predictions are based on empirical data, not speculation

**Implementation**:
```r
locations_with_data <- spawn_data %>%
  group_by(LocationCode) %>%
  filter(any(index > 0)) %>%  # At least one non-zero measurement
  ungroup()
```

### 3. Temporal Scope

**Decision**: Use 2015-2024 data (10-year window)

**Rationale**:
- Recent data more relevant for current predictions
- Balances between sufficient sample size and temporal relevance
- Captures recent environmental/ecological trends
- Aligns with typical fisheries management timeframes

### 4. Date Representation

**Decision**: Convert dates to Day-of-Year (DOY) for analysis

**Rationale**:
- Standardizes timing across years (e.g., Feb 15 = day 46)
- Enables calculation of average spawn timing
- Facilitates identification of early/late spawns
- Simplifies statistical modeling

**Implementation**:
```r
StartDOY = yday(StartDate)  # lubridate function
```

## Prediction Methodology

### Timing Predictions

**Method**: Historical average DOY ± 95% confidence intervals

**Formula**:
- Predicted date = Average DOY across 2016-2025
- 95% CI = Predicted DOY ± 1.96 × Standard Deviation

**Rationale**:
- Simple, transparent, interpretable
- Directly reflects observed historical patterns
- Confidence intervals capture natural variability
- Alternative GAM models were tested but showed over-fitting

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
- Conservative approach appropriate for management applications

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
   - 2024 spawn = 0.9
   - 2023 spawn = 0.6
   - 2020-2022 = 0.4
   - Pre-2020 = 0.2
   - 2019-2021 = 0.5
   - Pre-2019 = 0.3
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
- Missing data (NA) in biomass components = not surveyed (treated as 0)

### Limitations
- Climate change may alter spawn timing/locations
- Does not account for fish population dynamics
- Assumes spawn probability independent across locations
- Limited to locations with historical measurements

### Strengths
- Based on 10 years of empirical data
- Transparent, reproducible methodology
- Quantifies uncertainty with confidence intervals
- Conservative predictions appropriate for management

## Usage

### Requirements

Install required R packages:
```r
install.packages(c("dplyr", "lubridate", "leaflet", "ggpubr", 
                   "sf", "tidyr", "readr"))
```

### Running the Analysis

1. Clone this repository
2. Ensure `raw_data/Pacific_herring_spawn_index_data_2025_EN.csv` is present
3. Open RStudio and run:

```r
source("scripts/data_processing.R")
```

The script will:
- Load and process the data
- Generate 2026 predictions
- Create an interactive map (displayed in Viewer pane)
- Print summary statistics to console
- Display top 10 locations and earliest spawns

### Output

**Console Output**:
- Total locations analyzed
- Probability tier breakdown
- Predicted spawn season range
- Top 10 locations by biomass
- Earliest predicted spawns

**Map Output**:
- Interactive HTML map
- Click locations for detailed popups
- Pan/zoom for exploration

## Project Structure

```
herringspawnprediction/
├── README.md                    # This file
├── scripts/
│   └── data_processing.R        # Main analysis script
└── raw_data/
    └── Pacific_herring_spawn_index_data_2025_EN.csv
```

## Author

Developed for Pacific herring spawn prediction and management applications.

## Data Citation

Fisheries and Oceans Canada. Pacific Herring Spawn Index Data. 2025 Edition.

## License

This project is intended for research and educational purposes. Please cite appropriately if used in publications or reports.

---

**Last Updated**: January 2026  
**Analysis Period**: 2016-2025  
**Prediction Year**: 2026
