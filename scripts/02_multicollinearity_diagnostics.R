# ============================================================
# Project: Interpretable Modeling of New Vehicle Prices
# Script: 02_multicollinearity_diagnostics.R
# Purpose: Run formal multicollinearity diagnostics for the
#          interpretable pricing model
# ============================================================

# ---- Packages ----
library(readxl)
library(dplyr)
library(janitor)
library(readr)
library(tidyr)
library(ggplot2)
library(tibble)

# Optional packages
suppressWarnings({
  has_car <- requireNamespace("car", quietly = TRUE)
  has_olsrr <- requireNamespace("olsrr", quietly = TRUE)
})

# ---- Project folders ----
dir.create("outputs", showWarnings = FALSE)
dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables", showWarnings = FALSE, recursive = TRUE)

# ---- Load data ----
cars <- read_excel("data/04cars_data.xls") %>%
  clean_names()

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

# ---- Create markup for possible reference ----
cars <- cars %>%
  mutate(markup = retail_price - dealer_cost)

# ============================================================
# Modeling variable sets
# ============================================================

# Main interpretable set:
# dealer_cost excluded on purpose because it is nearly a proxy for retail_price
predictors_main <- c(
  "engine_size_l", "cyl", "hp",
  "city_mpg", "hwy_mpg",
  "weight", "wheel_base", "len", "width"
)
predictors_main <- predictors_main[predictors_main %in% names(cars)]

# Alternative set including dealer_cost only for diagnostic comparison
predictors_with_cost <- c("dealer_cost", predictors_main)
predictors_with_cost <- predictors_with_cost[predictors_with_cost %in% names(cars)]

# Keep complete cases for the selected predictors + target
model_df <- cars %>%
  select(retail_price, all_of(predictors_main)) %>%
  drop_na()

model_df_cost <- cars %>%
  select(retail_price, all_of(predictors_with_cost)) %>%
  drop_na()

cat("\nRows in main modeling dataset:", nrow(model_df), "\n")
cat("Rows in comparison dataset (with dealer_cost):", nrow(model_df_cost), "\n")

# ============================================================
# Baseline OLS for main interpretable model
# ============================================================

form_main <- as.formula(
  paste("retail_price ~", paste(predictors_main, collapse = " + "))
)

lm_main <- lm(form_main, data = model_df)

# Save coefficient table
coef_tbl <- summary(lm_main)$coefficients %>%
  as.data.frame() %>%
  rownames_to_column("term")

write_csv(coef_tbl, "outputs/tables/ols_main_coefficients.csv")

# ============================================================
# 1) Variance Inflation Factor (VIF)
# ============================================================

compute_vif_manual <- function(df_predictors) {
  var_names <- names(df_predictors)

  vif_vals <- sapply(var_names, function(v) {
    others <- setdiff(var_names, v)
    f <- as.formula(paste(v, "~", paste(others, collapse = " + ")))
    fit <- lm(f, data = df_predictors)
    r2 <- summary(fit)$r.squared
    1 / (1 - r2)
  })

  tibble(
    variable = names(vif_vals),
    vif = as.numeric(vif_vals)
  ) %>%
    arrange(desc(vif))
}

vif_tbl <- compute_vif_manual(model_df %>% select(-retail_price))

write_csv(vif_tbl, "outputs/tables/vif_main_model.csv")

# Comparison VIF including dealer_cost
vif_tbl_cost <- compute_vif_manual(model_df_cost %>% select(-retail_price))
write_csv(vif_tbl_cost, "outputs/tables/vif_model_with_dealer_cost.csv")

# Plot VIF
p_vif <- ggplot(vif_tbl, aes(x = reorder(variable, vif), y = vif)) +
  geom_col() +
  geom_hline(yintercept = 5, linetype = "dashed") +
  geom_hline(yintercept = 10, linetype = "dotted") +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Variance Inflation Factors (Main Interpretable Model)",
    x = NULL,
    y = "VIF"
  )

ggsave(
  "outputs/figures/vif_main_model.png",
  plot = p_vif,
  width = 8,
  height = 5,
  dpi = 200
)

# ============================================================
# 2) Condition Index / Eigenstructure Diagnostics
# ============================================================

compute_condition_index <- function(df_predictors) {
  X <- scale(as.matrix(df_predictors), center = TRUE, scale = TRUE)
  eig <- eigen(cor(X), symmetric = TRUE)

  eigenvalues <- eig$values
  condition_index <- sqrt(max(eigenvalues) / eigenvalues)

  tibble(
    dimension = seq_along(eigenvalues),
    eigenvalue = eigenvalues,
    condition_index = condition_index
  ) %>%
    arrange(desc(condition_index))
}

ci_tbl <- compute_condition_index(model_df %>% select(-retail_price))
write_csv(ci_tbl, "outputs/tables/condition_index_main_model.csv")

p_ci <- ggplot(ci_tbl, aes(x = reorder(as.factor(dimension), condition_index), y = condition_index)) +
  geom_col() +
  geom_hline(yintercept = 10, linetype = "dashed") +
  geom_hline(yintercept = 30, linetype = "dotted") +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Condition Index Diagnostics",
    x = "Dimension",
    y = "Condition Index"
  )

ggsave(
  "outputs/figures/condition_index_main_model.png",
  plot = p_ci,
  width = 8,
  height = 5,
  dpi = 200
)

# ============================================================
# 3) Correlation clusters among predictors only
# ============================================================

pred_corr <- cor(model_df %>% select(-retail_price), use = "pairwise.complete.obs")

pred_corr_long <- as.data.frame(pred_corr) %>%
  rownames_to_column("var1") %>%
  pivot_longer(-var1, names_to = "var2", values_to = "corr") %>%
  filter(var1 < var2) %>%
  mutate(abs_corr = abs(corr)) %>%
  arrange(desc(abs_corr))

write_csv(pred_corr_long, "outputs/tables/predictor_correlations_sorted.csv")

high_corr_tbl <- pred_corr_long %>%
  filter(abs_corr >= 0.75)

write_csv(high_corr_tbl, "outputs/tables/high_predictor_correlations_ge_0p75.csv")

# ============================================================
# 4) Coefficient instability checks
#    Compare related specifications to show coefficient movement
# ============================================================

# Candidate specifications
specs <- list(
  spec_1_all = c("engine_size_l", "cyl", "hp", "city_mpg", "hwy_mpg", "weight", "wheel_base", "len", "width"),
  spec_2_drop_city = c("engine_size_l", "cyl", "hp", "hwy_mpg", "weight", "wheel_base", "len", "width"),
  spec_3_drop_hwy = c("engine_size_l", "cyl", "hp", "city_mpg", "weight", "wheel_base", "len", "width"),
  spec_4_perf_only = c("engine_size_l", "cyl", "hp"),
  spec_5_size_only = c("weight", "wheel_base", "len", "width"),
  spec_6_reduced = c("hp", "hwy_mpg", "weight", "wheel_base", "width")
)

get_coef_table <- function(spec_name, vars, df) {
  vars <- vars[vars %in% names(df)]
  f <- as.formula(paste("retail_price ~", paste(vars, collapse = " + ")))
  fit <- lm(f, data = df)

  tibble(
    model = spec_name,
    term = names(coef(fit)),
    estimate = as.numeric(coef(fit))
  ) %>%
    filter(term != "(Intercept)")
}

coef_compare_tbl <- bind_rows(
  lapply(names(specs), function(nm) get_coef_table(nm, specs[[nm]], model_df))
)

write_csv(coef_compare_tbl, "outputs/tables/coefficient_instability_across_specs.csv")

p_coef_instability <- ggplot(coef_compare_tbl, aes(x = model, y = estimate)) +
  geom_point() +
  geom_line(aes(group = term)) +
  facet_wrap(~ term, scales = "free_y") +
  theme_minimal() +
  labs(
    title = "Coefficient Instability Across Alternative OLS Specifications",
    x = "Model Specification",
    y = "Coefficient Estimate"
  ) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(
  "outputs/figures/coefficient_instability_across_specs.png",
  plot = p_coef_instability,
  width = 12,
  height = 8,
  dpi = 200
)

# ============================================================
# 5) Standardized coefficients for the main OLS model
# ============================================================

model_df_std <- model_df %>%
  mutate(across(everything(), scale)) %>%
  as.data.frame()

lm_main_std <- lm(form_main, data = model_df_std)

std_coef_tbl <- summary(lm_main_std)$coefficients %>%
  as.data.frame() %>%
  rownames_to_column("term") %>%
  filter(term != "(Intercept)") %>%
  rename(
    std_estimate = Estimate,
    std_error = `Std. Error`,
    t_value = `t value`,
    p_value = `Pr(>|t|)`
  ) %>%
  arrange(desc(abs(std_estimate)))

write_csv(std_coef_tbl, "outputs/tables/standardized_coefficients_main_model.csv")

p_std_coef <- ggplot(std_coef_tbl, aes(x = reorder(term, abs(std_estimate)), y = std_estimate)) +
  geom_col() +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Standardized Coefficients (Main OLS Model)",
    x = NULL,
    y = "Standardized Coefficient"
  )

ggsave(
  "outputs/figures/standardized_coefficients_main_model.png",
  plot = p_std_coef,
  width = 8,
  height = 5,
  dpi = 200
)

# ============================================================
# 6) Optional package-based diagnostics
# ============================================================

if (has_car) {
  vif_car <- car::vif(lm_main)

  vif_car_tbl <- tibble(
    variable = names(vif_car),
    vif_car = as.numeric(vif_car)
  ) %>%
    arrange(desc(vif_car))

  write_csv(vif_car_tbl, "outputs/tables/vif_car_package_main_model.csv")
}

if (has_olsrr) {
  ols_vif_tbl <- olsrr::ols_vif_tol(lm_main)
  write.csv(ols_vif_tbl, "outputs/tables/vif_olsrr_main_model.csv", row.names = FALSE)
}

# ============================================================
# 7) Plain-English interpretation file
# ============================================================

max_vif <- max(vif_tbl$vif, na.rm = TRUE)
max_ci <- max(ci_tbl$condition_index, na.rm = TRUE)

vif_flag <- ifelse(max_vif >= 10, "severe", ifelse(max_vif >= 5, "moderate", "limited"))
ci_flag  <- ifelse(max_ci >= 30, "severe", ifelse(max_ci >= 10, "moderate", "limited"))

top_corr_pairs <- high_corr_tbl %>%
  mutate(line = paste0(var1, " <-> ", var2, " : r = ", round(corr, 3))) %>%
  pull(line)

interpret_lines <- c(
  "Multicollinearity Diagnostic Summary",
  "===================================",
  "",
  paste0("Rows used in main model: ", nrow(model_df)),
  paste0("Number of predictors in main interpretable model: ", length(predictors_main)),
  "",
  paste0("Maximum VIF: ", round(max_vif, 2), " (", vif_flag, " multicollinearity by common rule-of-thumb thresholds)"),
  paste0("Maximum condition index: ", round(max_ci, 2), " (", ci_flag, " near-dependency signal)"),
  "",
  "Strongest predictor-predictor correlations (|r| >= 0.75):"
)

if (length(top_corr_pairs) == 0) {
  interpret_lines <- c(interpret_lines, "None above threshold.")
} else {
  interpret_lines <- c(interpret_lines, paste0(" - ", top_corr_pairs))
}

interpret_lines <- c(
  interpret_lines,
  "",
  "Interpretation:",
  "The vehicle attributes contain overlapping information about underlying concepts such as performance, size, and fuel efficiency.",
  "This means ordinary least squares coefficients may be unstable or sensitive to specification changes even when the model has good overall fit.",
  "This finding motivates the next project step: compare OLS with ridge and lasso regularization."
)

writeLines(interpret_lines, "outputs/tables/multicollinearity_summary.txt")

# ============================================================
# 8) Console summary
# ============================================================

cat("\nDONE: 02_multicollinearity_diagnostics.R completed successfully.\n\n")
cat("Key outputs saved:\n")
cat("- outputs/tables/vif_main_model.csv\n")
cat("- outputs/tables/vif_model_with_dealer_cost.csv\n")
cat("- outputs/tables/condition_index_main_model.csv\n")
cat("- outputs/tables/high_predictor_correlations_ge_0p75.csv\n")
cat("- outputs/tables/coefficient_instability_across_specs.csv\n")
cat("- outputs/tables/standardized_coefficients_main_model.csv\n")
cat("- outputs/tables/multicollinearity_summary.txt\n")
cat("- outputs/figures/vif_main_model.png\n")
cat("- outputs/figures/condition_index_main_model.png\n")
cat("- outputs/figures/coefficient_instability_across_specs.png\n")
cat("- outputs/figures/standardized_coefficients_main_model.png\n\n")

cat("Quick read:\n")
cat("Max VIF =", round(max_vif, 2), "\n")
cat("Max condition index =", round(max_ci, 2), "\n")