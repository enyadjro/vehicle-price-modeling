# ============================================================
# Project: Interpretable Modeling of New Vehicle Prices
# Script: 04_linear_model_baseline.R
# Purpose: Fit and evaluate a baseline OLS model using the
#          engineered interpretable dataset
# ============================================================

# ---- Packages ----
library(dplyr)
library(readr)
library(ggplot2)
library(tibble)

# ---- Project folders ----
dir.create("outputs", showWarnings = FALSE)
dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/models", showWarnings = FALSE, recursive = TRUE)

# ============================================================
# 1) Load engineered interpretable dataset
# ============================================================
cars <- read_csv("outputs/data_clean/cars_model_interpretable.csv", show_col_types = FALSE)

# ============================================================
# 2) Keep variables needed for the baseline model
# ============================================================
model_vars <- c(
  "vehicle_name",
  "msrp",
  "log_msrp",
  "hp_per_1000lb",
  "mpg_mean",
  "mpg_gap",
  "log_engine_size",
  "log_weight",
  "log_footprint",
  "wb_to_len",
  "awd",
  "rwd",
  "vehicle_type"
)

model_df <- cars %>%
  select(all_of(model_vars)) %>%
  mutate(
    vehicle_type = as.factor(vehicle_type),
    awd = as.integer(awd),
    rwd = as.integer(rwd)
  ) %>%
  drop_na()

cat("\nRows available after complete-case filtering:", nrow(model_df), "\n")

# Save modeling dataset used by OLS
write_csv(model_df, "outputs/data_clean/baseline_model_dataset.csv")

# ============================================================
# 3) Train/test split
# ============================================================
set.seed(123)

n <- nrow(model_df)
train_idx <- sample(seq_len(n), size = floor(0.8 * n))

train_df <- model_df[train_idx, ]
test_df  <- model_df[-train_idx, ]

cat("Training rows:", nrow(train_df), "\n")
cat("Testing rows :", nrow(test_df), "\n")

# ============================================================
# 4) Baseline formula
# ============================================================
baseline_formula <- log_msrp ~ hp_per_1000lb + mpg_mean + mpg_gap +
  log_engine_size + log_weight + log_footprint + wb_to_len +
  awd + rwd + vehicle_type

# ============================================================
# 5) Fit baseline OLS
# ============================================================
lm_base <- lm(baseline_formula, data = train_df)

# Save model object
saveRDS(lm_base, "outputs/models/lm_baseline.rds")

# ============================================================
# 6) Save model summary tables
# ============================================================
coef_tbl <- summary(lm_base)$coefficients %>%
  as.data.frame() %>%
  rownames_to_column("term")

write_csv(coef_tbl, "outputs/tables/lm_baseline_coefficients.csv")

fit_stats_tbl <- tibble(
  metric = c("n_train", "n_test", "num_parameters", "r_squared_train", "adj_r_squared_train",
             "sigma_train", "aic_train", "bic_train"),
  value = c(
    nrow(train_df),
    nrow(test_df),
    length(coef(lm_base)),
    summary(lm_base)$r.squared,
    summary(lm_base)$adj.r.squared,
    summary(lm_base)$sigma,
    AIC(lm_base),
    BIC(lm_base)
  )
)

write_csv(fit_stats_tbl, "outputs/tables/lm_baseline_fit_stats.csv")

# ============================================================
# 7) Predictions
# ============================================================
train_df <- train_df %>%
  mutate(
    pred_log_msrp = predict(lm_base, newdata = train_df),
    pred_msrp = exp(pred_log_msrp)
  )

test_df <- test_df %>%
  mutate(
    pred_log_msrp = predict(lm_base, newdata = test_df),
    pred_msrp = exp(pred_log_msrp)
  )

# ============================================================
# 8) Evaluation metrics
# ============================================================
rmse <- function(actual, pred) {
  sqrt(mean((actual - pred)^2, na.rm = TRUE))
}

mae <- function(actual, pred) {
  mean(abs(actual - pred), na.rm = TRUE)
}

r2_manual <- function(actual, pred) {
  ss_res <- sum((actual - pred)^2, na.rm = TRUE)
  ss_tot <- sum((actual - mean(actual, na.rm = TRUE))^2, na.rm = TRUE)
  1 - ss_res / ss_tot
}

eval_tbl <- tibble(
  dataset = c("train", "test", "train", "test"),
  scale = c("log", "log", "usd", "usd"),
  rmse = c(
    rmse(train_df$log_msrp, train_df$pred_log_msrp),
    rmse(test_df$log_msrp, test_df$pred_log_msrp),
    rmse(train_df$msrp, train_df$pred_msrp),
    rmse(test_df$msrp, test_df$pred_msrp)
  ),
  mae = c(
    mae(train_df$log_msrp, train_df$pred_log_msrp),
    mae(test_df$log_msrp, test_df$pred_log_msrp),
    mae(train_df$msrp, train_df$pred_msrp),
    mae(test_df$msrp, test_df$pred_msrp)
  ),
  r_squared = c(
    r2_manual(train_df$log_msrp, train_df$pred_log_msrp),
    r2_manual(test_df$log_msrp, test_df$pred_log_msrp),
    r2_manual(train_df$msrp, train_df$pred_msrp),
    r2_manual(test_df$msrp, test_df$pred_msrp)
  )
)

write_csv(eval_tbl, "outputs/tables/lm_baseline_evaluation.csv")

# ============================================================
# 9) Residual diagnostics
# ============================================================
train_df <- train_df %>%
  mutate(
    residual_log = log_msrp - pred_log_msrp,
    fitted_log = pred_log_msrp
  )

# Residual vs fitted
p_resid <- ggplot(train_df, aes(x = fitted_log, y = residual_log)) +
  geom_point(alpha = 0.7) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  theme_minimal() +
  labs(
    title = "Baseline OLS: Residuals vs Fitted (Train)",
    x = "Fitted log(MSRP)",
    y = "Residuals"
  )

ggsave(
  "outputs/figures/lm_baseline_residuals_vs_fitted.png",
  plot = p_resid,
  width = 7,
  height = 5,
  dpi = 200
)

# QQ plot
qq_df <- tibble(
  sample = sort(train_df$residual_log),
  theoretical = qqnorm(train_df$residual_log, plot.it = FALSE)$x
)

p_qq <- ggplot(qq_df, aes(x = theoretical, y = sample)) +
  geom_point(alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  theme_minimal() +
  labs(
    title = "Baseline OLS: Normal Q-Q Plot of Residuals",
    x = "Theoretical Quantiles",
    y = "Sample Quantiles"
  )

ggsave(
  "outputs/figures/lm_baseline_qqplot.png",
  plot = p_qq,
  width = 7,
  height = 5,
  dpi = 200
)

# ============================================================
# 10) Actual vs predicted plots
# ============================================================
p_pred_log <- ggplot(test_df, aes(x = log_msrp, y = pred_log_msrp)) +
  geom_point(alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  theme_minimal() +
  labs(
    title = "Baseline OLS: Actual vs Predicted log(MSRP) (Test)",
    x = "Actual log(MSRP)",
    y = "Predicted log(MSRP)"
  )

ggsave(
  "outputs/figures/lm_baseline_actual_vs_predicted_log_test.png",
  plot = p_pred_log,
  width = 7,
  height = 5,
  dpi = 200
)

p_pred_usd <- ggplot(test_df, aes(x = msrp, y = pred_msrp)) +
  geom_point(alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  theme_minimal() +
  labs(
    title = "Baseline OLS: Actual vs Predicted MSRP (Test)",
    x = "Actual MSRP (USD)",
    y = "Predicted MSRP (USD)"
  )

ggsave(
  "outputs/figures/lm_baseline_actual_vs_predicted_usd_test.png",
  plot = p_pred_usd,
  width = 7,
  height = 5,
  dpi = 200
)

# ============================================================
# 11) Variable importance proxy from standardized refit
# ============================================================
train_std <- train_df %>%
  select(-vehicle_name, -msrp, -pred_log_msrp, -pred_msrp, -residual_log, -fitted_log) %>%
  mutate(
    vehicle_type = as.factor(vehicle_type)
  )

# Create standardized numeric columns only
numeric_cols <- names(train_std)[sapply(train_std, is.numeric)]
train_std[numeric_cols] <- lapply(train_std[numeric_cols], scale)

lm_std <- lm(baseline_formula, data = train_std)

std_coef_tbl <- summary(lm_std)$coefficients %>%
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

write_csv(std_coef_tbl, "outputs/tables/lm_baseline_standardized_coefficients.csv")

p_std_coef <- ggplot(std_coef_tbl, aes(x = reorder(term, abs(std_estimate)), y = std_estimate)) +
  geom_col() +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Baseline OLS: Standardized Coefficients",
    x = NULL,
    y = "Standardized Coefficient"
  )

ggsave(
  "outputs/figures/lm_baseline_standardized_coefficients.png",
  plot = p_std_coef,
  width = 8,
  height = 5,
  dpi = 200
)

# ============================================================
# 12) Plain-English summary
# ============================================================
test_log_rmse <- eval_tbl %>% filter(dataset == "test", scale == "log") %>% pull(rmse)
test_log_mae  <- eval_tbl %>% filter(dataset == "test", scale == "log") %>% pull(mae)
test_log_r2   <- eval_tbl %>% filter(dataset == "test", scale == "log") %>% pull(r_squared)

test_usd_rmse <- eval_tbl %>% filter(dataset == "test", scale == "usd") %>% pull(rmse)
test_usd_mae  <- eval_tbl %>% filter(dataset == "test", scale == "usd") %>% pull(mae)
test_usd_r2   <- eval_tbl %>% filter(dataset == "test", scale == "usd") %>% pull(r_squared)

top_terms <- std_coef_tbl %>%
  mutate(line = paste0(term, " : ", round(std_estimate, 3))) %>%
  pull(line)

summary_lines <- c(
  "Baseline OLS Model Summary",
  "==========================",
  "",
  paste0("Training rows: ", nrow(train_df)),
  paste0("Testing rows: ", nrow(test_df)),
  "",
  "Model formula:",
  "log_msrp ~ hp_per_1000lb + mpg_mean + mpg_gap + log_engine_size +",
  "           log_weight + log_footprint + wb_to_len + awd + rwd + vehicle_type",
  "",
  "Test-set performance:",
  paste0(" - RMSE (log scale): ", round(test_log_rmse, 4)),
  paste0(" - MAE  (log scale): ", round(test_log_mae, 4)),
  paste0(" - R^2  (log scale): ", round(test_log_r2, 4)),
  paste0(" - RMSE (USD scale): ", round(test_usd_rmse, 2)),
  paste0(" - MAE  (USD scale): ", round(test_usd_mae, 2)),
  paste0(" - R^2  (USD scale): ", round(test_usd_r2, 4)),
  "",
  "Largest standardized effects:",
  paste0(" - ", head(top_terms, 8)),
  "",
  "Interpretation:",
  "This baseline OLS model uses engineered variables to capture performance, fuel efficiency, vehicle size, drivetrain, and body type.",
  "It serves as the interpretable benchmark before applying ridge and lasso regularization.",
  "The next step is to compare whether regularization improves predictive stability and test-set performance."
)

writeLines(summary_lines, "outputs/tables/lm_baseline_summary.txt")

# ============================================================
# 13) Console output
# ============================================================
cat("\nDONE: 04_linear_model_baseline.R completed successfully.\n\n")
cat("Saved:\n")
cat("- outputs/models/lm_baseline.rds\n")
cat("- outputs/tables/lm_baseline_coefficients.csv\n")
cat("- outputs/tables/lm_baseline_fit_stats.csv\n")
cat("- outputs/tables/lm_baseline_evaluation.csv\n")
cat("- outputs/tables/lm_baseline_standardized_coefficients.csv\n")
cat("- outputs/tables/lm_baseline_summary.txt\n")
cat("- outputs/figures/lm_baseline_residuals_vs_fitted.png\n")
cat("- outputs/figures/lm_baseline_qqplot.png\n")
cat("- outputs/figures/lm_baseline_actual_vs_predicted_log_test.png\n")
cat("- outputs/figures/lm_baseline_actual_vs_predicted_usd_test.png\n")
cat("- outputs/figures/lm_baseline_standardized_coefficients.png\n\n")

cat("Quick test metrics:\n")
print(eval_tbl %>% filter(dataset == "test"))