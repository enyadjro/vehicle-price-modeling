# ============================================================
# Project: Interpretable Modeling of New Vehicle Prices
# Script: 01_data_exploration.R
# Purpose: Load data, clean variables, inspect structure, perform
#          exploratory analysis, and run explicit correlation-based
#          multicollinearity diagnostics
# ============================================================

# ---- Packages ----
library(readxl)
library(dplyr)
library(janitor)
library(ggplot2)
library(tidyr)
library(readr)
library(tibble)

# Optional packages for collinearity visuals
suppressWarnings({
  has_ggally   <- requireNamespace("GGally", quietly = TRUE)
  has_reshape2 <- requireNamespace("reshape2", quietly = TRUE)
  has_corrplot <- requireNamespace("corrplot", quietly = TRUE)
})

# ---- Project folders ----
dir.create("outputs", showWarnings = FALSE)
dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables", showWarnings = FALSE, recursive = TRUE)

# ---- Load data ----
cars <- read_excel("data/04cars_data.xls")

# ---- Clean column names ----
cars <- clean_names(cars)

# ---- Fix data types ----
num_cols <- c("city_mpg", "hwy_mpg", "weight", "wheel_base", "len", "width")
num_cols <- num_cols[num_cols %in% names(cars)]
cars[num_cols] <- lapply(cars[num_cols], function(x) as.numeric(trimws(as.character(x))))

maybe_num <- c("retail_price", "dealer_cost", "engine_size_l", "cyl", "hp")
maybe_num <- maybe_num[maybe_num %in% names(cars)]
cars[maybe_num] <- lapply(cars[maybe_num], function(x) as.numeric(as.character(x)))

bin_cols <- c(
  "small_sporty_compact_large_sedan", "sports_car", "suv", "wagon",
  "minivan", "pickup", "awd", "rwd"
)
bin_cols <- bin_cols[bin_cols %in% names(cars)]
cars[bin_cols] <- lapply(cars[bin_cols], function(x) as.integer(as.character(x)))

# ---- Inspect structure ----
str(cars)
summary(cars)

# ---- Missingness summary ----
missing_tbl <- cars %>%
  summarise(across(everything(), ~ sum(is.na(.)))) %>%
  pivot_longer(cols = everything(), names_to = "variable", values_to = "n_missing") %>%
  arrange(desc(n_missing))

write_csv(missing_tbl, "outputs/tables/missingness_summary.csv")

# ---- Sanity checks ----
stopifnot(all(c("retail_price", "dealer_cost") %in% names(cars)))

# ============================================================
# Feature construction
# ============================================================

cars <- cars %>%
  mutate(markup = retail_price - dealer_cost)

# ============================================================
# EDA: target and markup
# ============================================================

p_msrp <- ggplot(cars, aes(x = retail_price)) +
  geom_histogram(bins = 30) +
  labs(
    title = "Distribution of Retail Vehicle Price",
    x = "Retail Price (USD)",
    y = "Count"
  ) +
  theme_minimal()

ggsave(
  filename = "outputs/figures/eda_retail_price_distribution.png",
  plot = p_msrp,
  width = 8,
  height = 4,
  dpi = 200
)
print(p_msrp)

p_markup <- ggplot(cars, aes(x = markup)) +
  geom_histogram(bins = 30) +
  labs(
    title = "Distribution of Dealer Markup",
    x = "Markup = Retail Price - Dealer Cost (USD)",
    y = "Count"
  ) +
  theme_minimal()

ggsave(
  filename = "outputs/figures/eda_markup_distribution.png",
  plot = p_markup,
  width = 8,
  height = 4,
  dpi = 200
)
print(p_markup)

price_summary <- cars %>%
  summarise(
    n = n(),
    mean_retail_price = mean(retail_price, na.rm = TRUE),
    median_retail_price = median(retail_price, na.rm = TRUE),
    min_retail_price = min(retail_price, na.rm = TRUE),
    max_retail_price = max(retail_price, na.rm = TRUE),
    mean_markup = mean(markup, na.rm = TRUE),
    median_markup = median(markup, na.rm = TRUE),
    min_markup = min(markup, na.rm = TRUE),
    max_markup = max(markup, na.rm = TRUE)
  )

write_csv(price_summary, "outputs/tables/price_summary.csv")
print(price_summary)

# ============================================================
# EDA: category flags
# ============================================================

cat_flags <- c("sports_car", "suv", "wagon", "minivan", "pickup", "awd", "rwd")
cat_flags <- cat_flags[cat_flags %in% names(cars)]

for (flag in cat_flags) {
  p <- ggplot(cars, aes(x = factor(.data[[flag]]), y = retail_price)) +
    geom_boxplot() +
    labs(
      title = paste("Retail Price by", flag),
      x = paste(flag, "(0 = No, 1 = Yes)"),
      y = "Retail Price (USD)"
    ) +
    theme_minimal()

  out_file <- paste0("outputs/figures/eda_retail_price_by_", flag, ".png")
  ggsave(out_file, plot = p, width = 7, height = 4, dpi = 200)
  print(p)
}

for (flag in cat_flags) {
  p <- ggplot(cars, aes(x = factor(.data[[flag]]), y = markup)) +
    geom_boxplot() +
    labs(
      title = paste("Markup by", flag),
      x = paste(flag, "(0 = No, 1 = Yes)"),
      y = "Markup (USD)"
    ) +
    theme_minimal()

  out_file <- paste0("outputs/figures/eda_markup_by_", flag, ".png")
  ggsave(out_file, plot = p, width = 7, height = 4, dpi = 200)
  print(p)
}

if (length(cat_flags) > 0) {
  group_means <- lapply(cat_flags, function(flag) {
    cars %>%
      group_by(.data[[flag]]) %>%
      summarise(
        n = n(),
        mean_retail_price = mean(retail_price, na.rm = TRUE),
        median_retail_price = median(retail_price, na.rm = TRUE),
        mean_markup = mean(markup, na.rm = TRUE),
        median_markup = median(markup, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      rename(flag_value = 1) %>%
      mutate(flag = flag) %>%
      relocate(flag, flag_value)
  }) %>% bind_rows()

  write_csv(group_means, "outputs/tables/category_group_means.csv")
}

# ============================================================
# EDA: continuous predictors vs target
# ============================================================

cont_vars <- c(
  "dealer_cost", "engine_size_l", "cyl", "hp",
  "city_mpg", "hwy_mpg", "weight", "wheel_base", "len", "width"
)
cont_vars <- cont_vars[cont_vars %in% names(cars)]

for (v in cont_vars) {
  p <- ggplot(cars, aes(x = .data[[v]], y = retail_price)) +
    geom_point(alpha = 0.5) +
    geom_smooth(se = TRUE) +
    labs(
      title = paste("Retail Price vs", v),
      x = v,
      y = "Retail Price (USD)"
    ) +
    theme_minimal()

  out_file <- paste0("outputs/figures/eda_retail_price_vs_", v, ".png")
  ggsave(out_file, plot = p, width = 7, height = 4, dpi = 200)
  print(p)
}

# ============================================================
# Correlation-based multicollinearity diagnostics
# ============================================================

collinearity_vars <- c(
  "retail_price", "dealer_cost", "markup",
  "engine_size_l", "cyl", "hp", "city_mpg", "hwy_mpg",
  "weight", "wheel_base", "len", "width"
)
collinearity_vars <- collinearity_vars[collinearity_vars %in% names(cars)]

num_for_corr <- cars %>%
  select(all_of(collinearity_vars)) %>%
  mutate(across(everything(), ~ as.numeric(as.character(.))))

corr_mat <- cor(num_for_corr, use = "pairwise.complete.obs")

write_csv(
  as.data.frame(corr_mat) %>% rownames_to_column("variable"),
  "outputs/tables/correlation_matrix_numeric.csv"
)

corr_threshold <- 0.80

if (has_reshape2) {
  corr_pairs <- reshape2::melt(corr_mat, varnames = c("var1", "var2"), value.name = "corr") %>%
    filter(var1 < var2) %>%
    mutate(abs_corr = abs(corr)) %>%
    arrange(desc(abs_corr)) %>%
    filter(abs_corr >= corr_threshold)
} else {
  rn <- rownames(corr_mat)
  cn <- colnames(corr_mat)
  pairs <- expand.grid(var1 = rn, var2 = cn, stringsAsFactors = FALSE)
  pairs$corr <- as.vector(corr_mat)

  corr_pairs <- pairs %>%
    filter(var1 < var2) %>%
    mutate(abs_corr = abs(corr)) %>%
    arrange(desc(abs_corr)) %>%
    filter(abs_corr >= corr_threshold)
}

write_csv(corr_pairs, "outputs/tables/high_corr_pairs_ge_0p80.csv")

# ---- Correlation heatmap ----
if (has_corrplot) {
  png("outputs/figures/correlation_heatmap_numeric.png", width = 1400, height = 1100, res = 150)
  corrplot::corrplot(
    corr_mat,
    method = "color",
    type = "upper",
    order = "hclust",
    addCoef.col = "black",
    tl.col = "black",
    tl.srt = 45,
    number.cex = 0.7
  )
  dev.off()
} else {
  corr_df <- as.data.frame(corr_mat) %>%
    rownames_to_column("var1") %>%
    pivot_longer(-var1, names_to = "var2", values_to = "corr")

  p_corr <- ggplot(corr_df, aes(x = var2, y = var1, fill = corr)) +
    geom_tile() +
    geom_text(aes(label = sprintf("%.2f", corr)), size = 2.5) +
    scale_fill_gradient2(limits = c(-1, 1)) +
    labs(title = "Correlation Heatmap (Numeric Features)", x = NULL, y = NULL) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  ggsave("outputs/figures/correlation_heatmap_numeric.png", p_corr, width = 10, height = 8, dpi = 200)
  print(p_corr)
}

# ---- Pairs plot ----
if (has_ggally) {
  pairs_vars <- c(
    "retail_price", "engine_size_l", "cyl", "hp",
    "city_mpg", "hwy_mpg", "weight", "wheel_base", "len", "width"
  )
  pairs_vars <- pairs_vars[pairs_vars %in% names(num_for_corr)]

  p_pairs <- GGally::ggpairs(
    num_for_corr %>% select(all_of(pairs_vars)),
    upper = list(continuous = GGally::wrap("cor", size = 3)),
    lower = list(continuous = GGally::wrap("points", alpha = 0.25, size = 0.6)),
    diag  = list(continuous = GGally::wrap("densityDiag"))
  )

  ggsave(
    "outputs/figures/pairs_plot_numeric_features.png",
    plot = p_pairs,
    width = 12,
    height = 10,
    dpi = 200
  )
  print(p_pairs)
} else {
  message("GGally not installed -> skipping pairs plot. Install with install.packages('GGally')")
}

cat("\nDONE: 01_data_exploration.R completed successfully.\n")
cat("Saved: outputs/tables/missingness_summary.csv\n")
cat("Saved: outputs/tables/price_summary.csv\n")
cat("Saved: outputs/tables/correlation_matrix_numeric.csv\n")
cat("Saved: outputs/tables/high_corr_pairs_ge_0p80.csv\n")
cat("Saved: outputs/figures/correlation_heatmap_numeric.png\n")
cat("Saved: outputs/figures/pairs_plot_numeric_features.png (if GGally installed)\n")