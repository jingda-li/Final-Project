# Predicting the Earth Similarity Index of Exoplanets Using Stellar and Orbital Features

**Author:** Jingda Li
**Course:** ECON 626 Final Project
**Date:** April 13, 2026

## Overview

Can we tell how Earth-like a planet is just from its star and its orbit — without knowing anything about the planet itself? This project trains a random forest regression model to predict the **Earth Similarity Index (ESI)** of confirmed exoplanets using only **stellar**, **orbital**, and **system-level** features. Features describing a planet's physical composition (radius, mass, density, surface temperature) are deliberately excluded, so the model has to rely entirely on the properties of the host star and orbit.

## Motivation

The NASA Exoplanet Archive catalogs over 6,000 confirmed exoplanets, and a natural question is which of them most resemble Earth. ESI is a continuous score from 0 (completely unlike Earth) to 1 (identical to Earth), provided by the Habitable Worlds Catalog (HWC) from the Planetary Habitability Laboratory (PHL) @ UPR Arecibo.

Prior work (Jiang et al., 2024) modeled habitability as a *binary* classification problem. This project instead treats Earth-likeness as a *continuous* outcome (ESI) and restricts the feature set to stellar and orbital characteristics only, testing whether these alone carry meaningful signal about how Earth-like a planet is.

## Data Sources

| Dataset | Source | Purpose |
|---|---|---|
| Planetary Systems Composite Data | [NASA Exoplanet Archive](https://exoplanetarchive.ipac.caltech.edu) | Orbital, stellar, and system features |
| Habitable Worlds Catalog (HWC) | [PHL @ UPR Arecibo](https://phl.upr.edu/hwc) | ESI scores (response variable) |

The two datasets are joined on planet name, keeping only planets present in both.

**Note:** The raw data files (`PSCompPars.csv` and `hwc.csv`) are not included in this repository and must be downloaded separately from the links above to run the analysis script.

## Methodology

### Data Preparation
- Removed planets with a disputed (`pl_controv_flag`) confirmation status
- Restricted to single-host-star systems (`sy_snum == 1`)
- Dropped rows with missing ESI (the response variable)
- Explicitly excluded all planetary composition features (radius, mass, density, surface temperature)
- Retained orbital features (e.g., orbital period, eccentricity), stellar features (e.g., temperature, radius, spectral type), and system-level features (e.g., distance, discovery method)

### Preprocessing
- Decomposed stellar spectral type (`st_spectype`) into three ordinal features: spectral class, spectral subclass, and luminosity class
- Removed features with more than 25% missing values and near-zero-variance predictors
- One-hot encoded categorical variables (discovery method, metallicity ratio), with an "unknown" category for missing values
- Removed highly correlated numeric/ordinal features (correlation threshold of 0.8)
- All preprocessing parameters were fit on the training set only and applied to the test set to prevent data leakage
- Split data 80/20 into training and test sets, stratified on ESI

### Model
- **Random forest regression** (via `ranger`), chosen for its ability to capture non-linear relationships, robustness to correlated predictors, and interpretable feature importance
- Number of trees selected via out-of-bag (OOB) error convergence across 10–500 trees (500 trees used)
- Minimum node size tuned by minimizing OOB error across candidate values

## Results

- **Training (OOB) RMSE:** 0.0639
- **Test RMSE:** 0.0721

Since ESI ranges from 0–1 and most values in the dataset fall between 0.05 and 0.40, a test RMSE of 0.0721 indicates the model generalizes well and that stellar/orbital features are meaningfully — but not fully — predictive of Earth-likeness. The model performs well for low-ESI planets (the majority of the dataset) but tends to underpredict ESI for planets above 0.5.

**Most important predictors** (by permutation importance):
1. Orbital period (`pl_orbper`)
2. Stellar radius (`st_rad`)
3. Orbital eccentricity (`pl_orbeccen`)
4. H-band magnitude (`sy_hmag`)
5. Stellar effective temperature (`st_teff`)

## Repository Contents

| File | Description |
|---|---|
| `econ626_final_project.R` | Full analysis script: data loading, cleaning, preprocessing recipe, model tuning, fitting, and evaluation |
| `ECON_626_Research_Paper.pdf` | Full written report with methodology, results, and discussion |
| `ECON_626_Presentation_Slides.pdf` | Slide deck summarizing the project |

## Requirements

The R script uses the following packages:
- `tidyverse`
- `tidymodels`
- `ranger`
- `vip`

## Reproducing the Analysis

1. Download `PSCompPars.csv` (NASA Exoplanet Archive, Planetary Systems Composite Data) and `hwc.csv` (PHL Habitable Worlds Catalog) and place them in the working directory.
2. Install the required R packages listed above.
3. Run `econ626_final_project.R`. The script will:
   - Join and clean the datasets
   - Build and apply the preprocessing recipe
   - Tune and fit the random forest model
   - Output OOB/test metrics and generate the ESI distribution, predicted-vs-actual, and feature importance plots

## References

1. Jiang, J. H., Rosen, P. E., Liu, C. X., Wen, Q., & Chen, Y. (2024). Analysis of Habitability and Stellar Habitable Zones from Observed Exoplanets. *Galaxies*, 12(6), 86. https://doi.org/10.3390/galaxies12060086
2. NASA Exoplanet Archive. (2026). Planetary systems composite data. California Institute of Technology. https://exoplanetarchive.ipac.caltech.edu
3. Planetary Habitability Laboratory. (2024). Habitable worlds catalog. University of Puerto Rico at Arecibo. https://phl.upr.edu/hwc
