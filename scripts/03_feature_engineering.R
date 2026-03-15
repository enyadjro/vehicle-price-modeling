# ============================================================
# Project: Interpretable Modeling of New Vehicle Prices
# Script: 03_feature_engineering.R
# Purpose: Create engineered features for MSRP prediction,
#          document missingness after engineering, and save
#          modeling-ready datasets
# ============================================================

# ---- Packages ----
library(readxl)
library(dplyr)
library(janitor)
library(ggplot2)
library(tidyr)
library(readr)
library(tibble)

# ---- Project folders ----
dir.create("outputs", showWarnings = FALSE)
dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/data_clean", showWarnings = FALSE, recursive = TRUE)

# ============================================================
# 1) Load + clean
# ============================================================
cars <- read_excel("data/04cars_data.xls") %>%
  clean_names()

# Safer numeric parsing
num_cols <- c(
  "city_mpg", "hwy_mpg", "weight", "wheel_base", "len", "width",
  "retail_price", "dealer_cost", "engine_size_l", "cyl", "hp"
)

for (c in intersect(num_cols, names(cars))) {
  cars[[c]] <- parse_number(as.character(cars[[c]]))
}

# Ensure binary flags are integers
bin_cols <- c(
  "small_sporty_compact_large_sedan", "sports_car", "suv", "wagon",
  "minivan", "pickup", "awd", "rwd"
)

for (c in intersect(bin_cols, names(cars))) {
  cars[[c]] <- as.integer(cars[[c]])
}

cars_raw <- cars

# ============================================================
# 2) Define target and core price variables
# ============================================================
cars <- cars %>%
  rename(
    msrp = retail_price,
    invoice = dealer_cost
  ) %>%
  filter(!is.na(msrp), !is.na(invoice))

# ============================================================
# 3) Helper functions
# ============================================================
safe_log <- function(x) {
  ifelse(!is.na(x) & x > 0, log(x), NA_real_)
}

safe_divide <- function(num, den) {
  ifelse(!is.na(num) & !is.na(den) & den != 0, num / den, NA_real_)
}

# ============================================================
# 4) Engineer features
# ============================================================
cars <- cars %>%
  mutate(
    # --------------------------------
    # Pricing features
    # --------------------------------
    markup_usd = msrp - invoice,
    markup_pct = ifelse(!is.na(invoice) & invoice > 0,
                        (msrp - invoice) / invoice,
                        NA_real_),

    # --------------------------------
    # Fuel economy features
    # mpg_mean reduces city/hwy redundancy
    # mpg_gap captures city-vs-highway spread
    # --------------------------------
    mpg_mean = case_when(
      !is.na(city_mpg) & !is.na(hwy_mpg) ~ (city_mpg + hwy_mpg) / 2,
      !is.na(city_mpg) &  is.na(hwy_mpg) ~ city_mpg,
       is.na(city_mpg) & !is.na(hwy_mpg) ~ hwy_mpg,
      TRUE ~ NA_real_
    ),
    mpg_gap = ifelse(!is.na(city_mpg) & !is.na(hwy_mpg),
                     hwy_mpg - city_mpg,
                     NA_real_),

    # --------------------------------
    # Performance / weight features
    # --------------------------------
    hp_per_lb = safe_divide(hp, weight),
    hp_per_1000lb = ifelse(!is.na(hp) & !is.na(weight) & weight > 0,
                           hp / (weight / 1000),
                           NA_real_),

    # --------------------------------
    # Vehicle geometry features
    # --------------------------------
    footprint = ifelse(!is.na(len) & !is.na(width), len * width, NA_real_),
    wb_to_len = safe_divide(wheel_base, len),

    # --------------------------------
    # Special engine indicator
    # rotary engines are encoded as cyl == -1 in some cases
    # --------------------------------
    is_rotary = ifelse(!is.na(cyl) & cyl == -1, 1L, 0L)
  )

# --------------------------------
# Log transforms
# --------------------------------
cars <- cars %>%
  mutate(
    log_msrp        = safe_log(msrp),
    log_invoice     = safe_log(invoice),
    log_weight      = safe_log(weight),
    log_hp          = safe_log(hp),
    log_engine_size = safe_log(engine_size_l),
    log_footprint   = safe_log(footprint),
    log_markup_usd  = safe_log(markup_usd + 1)
  )

# ============================================================
# 5) Consolidated vehicle type label
# ============================================================
cars <- cars %>%
  mutate(
    vehicle_type = case_when(
      sports_car == 1 ~ "Sports Car",
      suv == 1        ~ "SUV",
      pickup == 1     ~ "Pickup",
      minivan == 1    ~ "Minivan",
      wagon == 1      ~ "Wagon",
      TRUE            ~ "Sedan/Other"
    ),
    vehicle_type = factor(
      vehicle_type,
      levels = c("Sedan/Other", "SUV", "Pickup", "Minivan", "Wagon", "Sports Car")
    )
  )

# ============================================================
# 6) Missingness after feature engineering
# ============================================================
feature_missing <- cars %>%
  summarise(across(everything(), ~ sum(is.na(.)))) %>%
  pivot_longer(
    cols = everything(),
    names_to = "feature",
    values_to = "n_missing"
  ) %>%
  mutate(
    pct_missing = round(100 * n_missing / nrow(cars), 2)
  ) %>%
  arrange(desc(n_missing), desc(pct_missing), feature)

write_csv(
  feature_missing,
  "outputs/tables/feature_missingness_after_engineering.csv"
)

# ============================================================
# 7) Feature documentation table
# ============================================================
feature_documentation <- tibble(
  feature = c(
    "msrp", "invoice", "markup_usd", "markup_pct",
    "mpg_mean", "mpg_gap",
    "hp_per_lb", "hp_per_1000lb",
    "footprint", "wb_to_len",
    "is_rotary",
    "log_msrp", "log_invoice", "log_weight",
    "log_hp", "log_engine_size", "log_footprint", "log_markup_usd",
    "vehicle_type"
  ),
  description = c(
    "Manufacturer's suggested retail price; target variable",
    "Dealer cost / invoice price",
    "Absolute markup in USD: msrp - invoice",
    "Relative markup as a share of invoice price",
    "Average fuel economy combining city and highway MPG",
    "Difference between highway and city MPG",
    "Horsepower divided by vehicle weight",
    "Horsepower per 1000 lb; interpretable power-to-weight metric",
    "Vehicle footprint computed as length × width",
    "Wheelbase-to-length ratio; captures vehicle proportions",
    "Indicator for rotary engine coding (cyl == -1)",
    "Natural log of MSRP",
    "Natural log of invoice price",
    "Natural log of weight",
    "Natural log of horsepower",
    "Natural log of engine size",
    "Natural log of footprint",
    "Natural log of markup_usd + 1",
    "Consolidated vehicle body-type label"
  ),
  role = c(
    "target", "raw", "engineered", "engineered",
    "engineered", "engineered",
    "engineered", "engineered",
    "engineered", "engineered",
    "engineered",
    "transformed_target", "transformed", "transformed",
    "transformed", "transformed", "transformed", "transformed",
    "categorical_engineered"
  )
)

write_csv(
  feature_documentation,
  "outputs/tables/feature_documentation.csv"
)

# ============================================================
# 8) Save engineered datasets
# ============================================================

# Full engineered dataset
write_csv(cars, "outputs/data_clean/cars_model_ready_full.csv")

# Slim general modeling dataset
cars_model_slim <- cars %>%
  select(
    vehicle_name,
    msrp, log_msrp,
    invoice, log_invoice,
    markup_usd, markup_pct,
    engine_size_l, log_engine_size, cyl, is_rotary,
    hp, log_hp, weight, log_weight,
    city_mpg, hwy_mpg, mpg_mean, mpg_gap,
    wheel_base, len, width, footprint, log_footprint, wb_to_len,
    hp_per_lb, hp_per_1000lb,
    awd, rwd,
    sports_car, suv, wagon, minivan, pickup,
    vehicle_type
  )

write_csv(
  cars_model_slim,
  "outputs/data_clean/cars_model_ready_slim.csv"
)

# Interpretable-modeling dataset
# Designed to support the later OLS / Ridge / Lasso comparison
# using engineered features that reduce some redundancy
cars_model_interpretable <- cars %>%
  select(
    vehicle_name,
    msrp, log_msrp,
    engine_size_l, log_engine_size,
    cyl, hp, log_hp,
    weight, log_weight,
    mpg_mean, mpg_gap,
    footprint, log_footprint,
    wb_to_len,
    hp_per_1000lb,
    awd, rwd,
    sports_car, suv, wagon, minivan, pickup,
    vehicle_type
  )

write_csv(
  cars_model_interpretable,
  "outputs/data_clean/cars_model_interpretable.csv"
)

# ============================================================
# 9) Optional complete-case modeling dataset
#    Saved separately for convenience, but not used automatically
# ============================================================
cars_model_interpretable_complete <- cars_model_interpretable %>%
  drop_na()

write_csv(
  cars_model_interpretable_complete,
  "outputs/data_clean/cars_model_interpretable_complete_cases.csv"
)

# ============================================================
# 10) Key plots
# ============================================================

p1 <- ggplot(cars, aes(x = msrp)) +
  geom_histogram(bins = 30) +
  labs(
    title = "MSRP Distribution",
    x = "MSRP (USD)",
    y = "Count"
  ) +
  theme_minimal()

ggsave(
  "outputs/figures/feat_msrp_distribution.png",
  plot = p1,
  width = 8,
  height = 4,
  dpi = 200
)

p2 <- ggplot(cars, aes(x = log_msrp)) +
  geom_histogram(bins = 30) +
  labs(
    title = "Log(MSRP) Distribution",
    x = "log(MSRP)",
    y = "Count"
  ) +
  theme_minimal()

ggsave(
  "outputs/figures/feat_log_msrp_distribution.png",
  plot = p2,
  width = 8,
  height = 4,
  dpi = 200
)

p3 <- ggplot(cars, aes(x = vehicle_type, y = msrp)) +
  geom_boxplot() +
  coord_flip() +
  labs(
    title = "MSRP by Vehicle Type",
    x = "",
    y = "MSRP (USD)"
  ) +
  theme_minimal()

ggsave(
  "outputs/figures/feat_msrp_by_vehicle_type.png",
  plot = p3,
  width = 8,
  height = 5,
  dpi = 200
)

p4 <- ggplot(cars, aes(x = hp_per_1000lb, y = msrp)) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(
    title = "MSRP vs Power-to-Weight",
    x = "HP per 1000 lb",
    y = "MSRP (USD)"
  ) +
  theme_minimal()

ggsave(
  "outputs/figures/feat_msrp_vs_power_to_weight.png",
  plot = p4,
  width = 8,
  height = 5,
  dpi = 200
)

p5 <- ggplot(cars, aes(x = mpg_mean, y = msrp)) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(
    title = "MSRP vs Average MPG",
    x = "Average MPG",
    y = "MSRP (USD)"
  ) +
  theme_minimal()

ggsave(
  "outputs/figures/feat_msrp_vs_mpg_mean.png",
  plot = p5,
  width = 8,
  height = 5,
  dpi = 200
)

p6 <- ggplot(cars, aes(x = footprint, y = msrp)) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(
    title = "MSRP vs Vehicle Footprint",
    x = "Footprint (length × width)",
    y = "MSRP (USD)"
  ) +
  theme_minimal()

ggsave(
  "outputs/figures/feat_msrp_vs_footprint.png",
  plot = p6,
  width = 8,
  height = 5,
  dpi = 200
)

# ============================================================
# 11) Console summary
# ============================================================
message("DONE: 03_feature_engineering.R completed successfully.")
message("Saved: outputs/data_clean/cars_model_ready_full.csv")
message("Saved: outputs/data_clean/cars_model_ready_slim.csv")
message("Saved: outputs/data_clean/cars_model_interpretable.csv")
message("Saved: outputs/data_clean/cars_model_interpretable_complete_cases.csv")
message("Saved: outputs/tables/feature_missingness_after_engineering.csv")
message("Saved: outputs/tables/feature_documentation.csv")