#ECON 626 Final Project

library(tidyverse)
library(tidymodels)
library(ranger)
library(vip)

#-------------------------------------------------------------------
#Import the datasets
#-------------------------------------------------------------------

nasa_data <- read_csv("PSCompPars.csv")
hwc_data <- read_csv("hwc.csv")

glimpse(hwc_data)

#Join the two datasets based on planet name

planets_df <- nasa_data %>%
  inner_join(hwc_data %>% select(pl_name = P_NAME, P_ESI),
             by = "pl_name")


cat("Rows after join:", nrow(planets_df), "\n")

#Perform initial feature selection and row filtering

# Remove controversial planets
planets_df <- planets_df %>% filter(pl_controv_flag == 0 | is.na(pl_controv_flag))
cat("After removing controversial planets:", nrow(planets_df), "\n")

# Keep only single host star systems
planets_df <- planets_df %>% filter(sy_snum == 1)
cat("After keeping single host systems:", nrow(planets_df), "\n")

# Drop rows with missing response (ESI)
planets_df <- planets_df %>% filter(!is.na(P_ESI))
cat("After dropping missing ESI:", nrow(planets_df), "\n")

#Remove all clearly irrelevant features for the project and
#keep only the most relevent features in the combined dataset. (Justify in paper)

planets_df <- planets_df %>%
  select(
    # Orbital features
    pl_orbper, pl_orbsmax, pl_orbeccen, pl_rvamp,
    # Stellar features
    st_spectype, st_teff, st_rad, st_mass,
    st_met, st_metratio, st_lum, st_logg,
    st_age, st_dens, st_vsin, st_radv,
    # System features
    sy_pnum, sy_mnum, sy_dist, sy_plx,
    sy_vmag, sy_jmag, sy_hmag, sy_kmag,
    sy_gaiamag, sy_tmag, discoverymethod,
    # Response variate
    P_ESI
  )

cat("Columns after feature selection:", ncol(planets_df), "\n")

planets_df <- planets_df %>%
  mutate(st_metratio = str_replace(st_metratio, "\\[m/H\\]", "[M/H]"))

#Split the dataset into a training dataset and a test dataset
set.seed(626)
split <- initial_split(planets_df, prop = 0.8, strata = P_ESI)
train_data <- training(split)
test_data  <- testing(split)

cat("Training set size:", nrow(train_data), "\n")
cat("Test set size:    ", nrow(test_data), "\n")

#Define a recipe for preprocessing

rf_recipe <- recipe(P_ESI ~ ., data = train_data) %>%
  
  
  #Construct three new features, spectral class, spectral subclass, and
  #luminosity class from spectral type (st_spectype). 
  #Then, ordinal encode the three newly constructed features. 
  step_mutate(
    # Spectral class — ordinal (temperature ordering)
    st_spectype_class = case_when(
      str_detect(st_spectype, "^O") ~ 1,
      str_detect(st_spectype, "^B") ~ 2,
      str_detect(st_spectype, "^A") ~ 3,
      str_detect(st_spectype, "^F") ~ 4,
      str_detect(st_spectype, "^G") ~ 5,
      str_detect(st_spectype, "^K") ~ 6,
      str_detect(st_spectype, "^M") ~ 7,
      TRUE ~ NA_real_
    ),
    
    # Spectral subclass — numeric (finer temperature within class)
    st_spectype_subclass = as.numeric(
      str_extract(st_spectype, "(?<=[OBAFGKM])[0-9]+\\.?[0-9]*")
    ),
    
    # Luminosity class — ordinal (dwarf to supergiant)
    # Note: check for III and II before I to avoid partial matching
    st_luminosity_class = case_when(
      str_detect(st_spectype, "Ia\\+") ~ 10,  # Hypergiant
      str_detect(st_spectype, "Iab")   ~ 8,   # Intermediate supergiant
      str_detect(st_spectype, "Ia")    ~ 9,   # Luminous supergiant
      str_detect(st_spectype, "Ib")    ~ 7,   # Less luminous supergiant
      str_detect(st_spectype, "VII")   ~ 1,   # White dwarf
      str_detect(st_spectype, "III")   ~ 5,   # Giant
      str_detect(st_spectype, "II")    ~ 6,   # Bright giant
      str_detect(st_spectype, "VI")    ~ 2,   # Subdwarf
      str_detect(st_spectype, "IV")    ~ 4,   # Subgiant
      str_detect(st_spectype, "sd")    ~ 2,   # Subdwarf alternative notation
      str_detect(st_spectype, "V")     ~ 3,   # Main sequence dwarf
      TRUE ~ NA_real_
    )
  ) %>%
  step_rm(st_spectype) %>%
  
  # Remove features missing more than 25% of values
  step_filter_missing(all_predictors(), threshold = 0.25) %>%
  
  # Remove near-zero variance predictors (e.g. constant columns)
  step_nzv(all_predictors()) %>%
  
  # Handle unknown/NA levels in categorical variables before one-hot encoding
  step_unknown(any_of(c("discoverymethod", "st_metratio")), 
               new_level = "unknown") %>%
  
  # One-hot encode nominal categorical variables
  step_dummy(any_of(c("discoverymethod", "st_metratio")), 
           one_hot = TRUE) %>%
  
  # Remove remaining rows with any missing values
  step_naomit(all_predictors(), all_outcomes()) %>%
  
  # Remove highly correlated continuous and ordinal features 
  step_corr(all_numeric_predictors(),
            -starts_with("discoverymethod_"),
            -starts_with("st_metratio_"),
            threshold = 0.8)

# Prep recipe on training data and inspect retained features
recipe_prepped <- prep(rf_recipe, training = train_data)

cat("\nFeatures retained after preprocessing:\n")
print(
  summary(recipe_prepped) %>%
    filter(role == "predictor") %>%
    pull(variable)
)

#Check ESI distribution in the training and test datasets 

train_baked <- bake(recipe_prepped, new_data = train_data)
test_baked  <- bake(recipe_prepped, new_data = test_data)


par(mfrow = c(1, 2))

hist(train_baked$P_ESI,
     breaks = 50,
     main   = "ESI Distribution — Training Set",
     xlab   = "ESI",
     col    = "steelblue",
     border = "white")

hist(test_baked$P_ESI,
     breaks = 50,
     main   = "ESI Distribution — Test Set",
     xlab   = "ESI",
     col    = "darkorange",
     border = "white")

par(mfrow = c(1, 1))

cat("Training set ESI summary:\n")
print(summary(train_baked$P_ESI))

cat("\nTest set ESI summary:\n")
print(summary(test_baked$P_ESI))

#The number of features in the baked training dataset
p <- ncol(train_baked) - 1

#Specify a random forest regression model
rf_spec <- rand_forest(
  trees = 500,
  mtry = floor(p/3), #default
  min_n = tune()
) %>%
  set_engine("ranger",
             importance = "permutation",
             seed       = 626) %>%
  set_mode("regression")

# Create workflow with tunable model
rf_workflow_tune <- workflow() %>%
  add_recipe(rf_recipe) %>%
  add_model(rf_spec)

#Choose the optimal number of trees using an OOB error plot

# Fit ranger directly with increasing numbers of trees
# and record OOB RMSE at each point
trees_grid <- seq(10, 500, by = 10)

oob_rmse <- numeric(length(trees_grid))

for (i in seq_along(trees_grid)) {
  fit_i <- ranger::ranger(
    P_ESI ~ .,
    data          = train_baked,
    num.trees     = trees_grid[i],
    mtry          = floor(p / 3),
    min.node.size = 5,
    seed          = 626,
    verbose       = FALSE
  )
  oob_rmse[i] <- sqrt(fit_i$prediction.error)
}

# Plot OOB RMSE vs number of trees
oob_errors <- data.frame(
  trees    = trees_grid,
  oob_rmse = oob_rmse
)

ggplot(oob_errors, aes(x = trees, y = oob_rmse)) +
  geom_line(color = "steelblue") +
  labs(
    title = "OOB RMSE vs Number of Trees",
    x     = "Number of Trees",
    y     = "OOB RMSE"
  ) +
  theme_minimal(base_size = 13)


# Tune min_n USING OOB error
min_n_candidates <- c(2, 5, 10, 15, 20, 30, 50)
min_n_oob_rmse   <- numeric(length(min_n_candidates))

for (i in seq_along(min_n_candidates)) {
  fit_i <- ranger::ranger(
    P_ESI ~ .,
    data          = train_baked,
    num.trees     = 500,
    mtry          = floor(p / 3),
    min.node.size = min_n_candidates[i],
    seed          = 626,
    verbose       = FALSE
  )
  min_n_oob_rmse[i] <- sqrt(fit_i$prediction.error)
}

# Plot OOB RMSE vs min_n
min_n_results <- data.frame(
  min_n    = min_n_candidates,
  oob_rmse = min_n_oob_rmse
)

ggplot(min_n_results, aes(x = min_n, y = oob_rmse)) +
  geom_line(color = "steelblue") +
  geom_point(color = "steelblue", size = 3) +
  labs(
    title = "OOB RMSE vs Minimum Node Size",
    x     = "Minimum Node Size (min_n)",
    y     = "OOB RMSE"
  ) +
  theme_minimal(base_size = 13)

# Select best min_n — the value with lowest OOB RMSE
best_min_n_val <- min_n_candidates[which.min(min_n_oob_rmse)]
cat("\nTuning results:\n")
print(min_n_results)
cat("\nBest min_n:", best_min_n_val, "\n")


#Finalize workflow 

# Update rf_spec with the best min_n found via OOB tuning
rf_spec_final <- rand_forest(
  trees = 500,
  mtry  = floor(p / 3),
  min_n = best_min_n_val
) %>%
  set_engine("ranger",
             importance = "permutation",
             seed       = 626) %>%
  set_mode("regression")

rf_workflow_final <- workflow() %>%
  add_recipe(rf_recipe) %>%
  add_model(rf_spec_final)


#Fit final model on the training set

set.seed(626)
rf_fit        <- rf_workflow_final %>% fit(data = train_data)
rf_engine     <- extract_fit_engine(rf_fit)

cat("\n===== TRAINING EVALUATION (OOB) =====\n")
cat("OOB R-squared:", round(rf_engine$r.squared, 4), "\n")
cat("OOB RMSE:     ", round(sqrt(rf_engine$prediction.error), 4), "\n")

#Evaluate the model on the test set

test_predictions <- rf_fit %>%
  predict(new_data = test_data) %>%
  bind_cols(test_baked %>% select(P_ESI))

# Compute test set metrics
test_metrics <- test_predictions %>%
  metrics(truth = P_ESI, estimate = .pred)

cat("\n===== TEST SET EVALUATION =====\n")
print(test_metrics)

# Predicted vs actual plot
ggplot(test_predictions, aes(x = P_ESI, y = .pred)) +
  geom_point(alpha = 0.5, color = "steelblue") +
  geom_abline(slope = 1, intercept = 0,
              color = "red", linewidth = 1) +
  labs(
    title = "Predicted vs Actual ESI (Test Set)",
    x     = "Actual ESI",
    y     = "Predicted ESI"
  ) +
  theme_minimal(base_size = 13)

#Feature importance plot

rf_fit %>%
  extract_fit_parsnip() %>%
  vip(
    num_features = 20,
    aesthetics   = list(fill = "steelblue")
  ) +
  labs(
    title = "Feature Importance for Predicting\nExoplanet Earth Similarity Index",
    x     = "Feature",
    y     = "Feature Importance"
  ) +
  theme_minimal(base_size = 13)
