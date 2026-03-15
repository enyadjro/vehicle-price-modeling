# ============================================================
# Project: Interpretable Modeling of New Vehicle Prices
# Script: 05_regularized_models.R
# Purpose: Fit Ridge, Lasso, and Elastic Net models and compare
#          them against the baseline OLS benchmark
# ============================================================

# ---- Packages ----
library(dplyr)
library(readr)
library(ggplot2)
library(tibble)
library(glmnet)

# ---- Project folders ----
dir.create("outputs", showWarnings = FALSE)
dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/models", showWarnings = FALSE, recursive = TRUE)

# ============================================================
# 1) Load baseline modeling dataset
# ============================================================
model_df <- read_csv("outputs/data_clean/baseline_model_dataset.csv", show_col_types = FALSE)

# Safety checks
stopifnot(all(c("msrp", "log_msrp") %in% names(model_df)))

# ============================================================
# 2) Recreate the same train/test split used in Script 04
# ============================================================
set.seed(123)

n <- nrow(model_df)
train_idx <- sample(seq_len(n), size = floor(0.8 * n))

train_df <- model_df[train_idx, ]
test_df  <- model_df[-train_idx, ]

cat("\nTraining rows:", nrow(train_df), "\n")
cat("Testing rows :", nrow(test_df), "\n")

# ============================================================
# 3) Build model matrices
# ============================================================
# Use the same baseline formula terms, but glmnet needs x/y matrices.
x_formula <- ~ hp_per_1000lb + mpg_mean + mpg_gap +
  log_engine_size + log_weight + log_footprint + wb_to_len +
  awd + rwd + vehicle_type

x_train <- model.matrix(x_formula, data = train_df)[, -1]
x_test  <- model.matrix(x_formula, data = test_df)[, -1]

y_train <- train_df$log_msrp
y_test  <- test_df$log_msrp

feature_names <- colnames(x_train)

# ============================================================
# 4) Metric helpers
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

evaluate_preds <- function(actual_log, pred_log, actual_usd) {
  pred_usd <- exp(pred_log)

  tibble(
    rmse_log = rmse(actual_log, pred_log),
    mae_log = mae(actual_log, pred_log),
    r2_log = r2_manual(actual_log, pred_log),
    rmse_usd = rmse(actual_usd, pred_usd),
    mae_usd = mae(actual_usd, pred_usd),
    r2_usd = r2_manual(actual_usd, pred_usd)
  )
}

# ============================================================
# 5) Fit regularized models with CV
# ============================================================
set.seed(123)

# Ridge: alpha = 0
cv_ridge <- cv.glmnet(
  x = x_train,
  y = y_train,
  alpha = 0,
  nfolds = 10,
  standardize = TRUE
)

# Lasso: alpha = 1
cv_lasso <- cv.glmnet(
  x = x_train,
  y = y_train,
  alpha = 1,
  nfolds = 10,
  standardize = TRUE
)

# Elastic Net: alpha = 0.5
cv_enet <- cv.glmnet(
  x = x_train,
  y = y_train,
  alpha = 0.5,
  nfolds = 10,
  standardize = TRUE
)

# Save model objects
saveRDS(cv_ridge, "outputs/models/cv_ridge.rds")
saveRDS(cv_lasso, "outputs/models/cv_lasso.rds")
saveRDS(cv_enet,  "outputs/models/cv_elastic_net.rds")

# Also save full path fits for coefficient-path plots
ridge_fit <- glmnet(x_train, y_train, alpha = 0, standardize = TRUE)
lasso_fit <- glmnet(x_train, y_train, alpha = 1, standardize = TRUE)
enet_fit  <- glmnet(x_train, y_train, alpha = 0.5, standardize = TRUE)

saveRDS(ridge_fit, "outputs/models/ridge_fit_path.rds")
saveRDS(lasso_fit, "outputs/models/lasso_fit_path.rds")
saveRDS(enet_fit,  "outputs/models/elastic_net_fit_path.rds")

# ============================================================
# 6) Predictions using lambda.min and lambda.1se
# ============================================================
pred_ridge_min <- as.numeric(predict(cv_ridge, newx = x_test, s = "lambda.min"))
pred_ridge_1se <- as.numeric(predict(cv_ridge, newx = x_test, s = "lambda.1se"))

pred_lasso_min <- as.numeric(predict(cv_lasso, newx = x_test, s = "lambda.min"))
pred_lasso_1se <- as.numeric(predict(cv_lasso, newx = x_test, s = "lambda.1se"))

pred_enet_min <- as.numeric(predict(cv_enet, newx = x_test, s = "lambda.min"))
pred_enet_1se <- as.numeric(predict(cv_enet, newx = x_test, s = "lambda.1se"))

# ============================================================
# 7) Evaluation tables
# ============================================================
eval_ridge_min <- evaluate_preds(y_test, pred_ridge_min, test_df$msrp) %>%
  mutate(model = "ridge", lambda_choice = "lambda.min")

eval_ridge_1se <- evaluate_preds(y_test, pred_ridge_1se, test_df$msrp) %>%
  mutate(model = "ridge", lambda_choice = "lambda.1se")

eval_lasso_min <- evaluate_preds(y_test, pred_lasso_min, test_df$msrp) %>%
  mutate(model = "lasso", lambda_choice = "lambda.min")

eval_lasso_1se <- evaluate_preds(y_test, pred_lasso_1se, test_df$msrp) %>%
  mutate(model = "lasso", lambda_choice = "lambda.1se")

eval_enet_min <- evaluate_preds(y_test, pred_enet_min, test_df$msrp) %>%
  mutate(model = "elastic_net", lambda_choice = "lambda.min")

eval_enet_1se <- evaluate_preds(y_test, pred_enet_1se, test_df$msrp) %>%
  mutate(model = "elastic_net", lambda_choice = "lambda.1se")

regularized_eval_tbl <- bind_rows(
  eval_ridge_min,
  eval_ridge_1se,
  eval_lasso_min,
  eval_lasso_1se,
  eval_enet_min,
  eval_enet_1se
) %>%
  select(model, lambda_choice, everything())

write_csv(
  regularized_eval_tbl,
  "outputs/tables/regularized_model_evaluation.csv"
)

# ============================================================
# 8) Save lambda summary
# ============================================================
lambda_tbl <- tibble(
  model = c("ridge", "lasso", "elastic_net"),
  lambda_min = c(cv_ridge$lambda.min, cv_lasso$lambda.min, cv_enet$lambda.min),
  lambda_1se = c(cv_ridge$lambda.1se, cv_lasso$lambda.1se, cv_enet$lambda.1se)
)

write_csv(lambda_tbl, "outputs/tables/regularized_lambda_summary.csv")

# ============================================================
# 9) Extract coefficient tables
# ============================================================
coef_to_tbl <- function(cv_fit, s_value, model_name) {
  mat <- as.matrix(coef(cv_fit, s = s_value))
  tibble(
    term = rownames(mat),
    estimate = as.numeric(mat[, 1]),
    model = model_name,
    lambda_choice = s_value
  )
}

coef_tbl_all <- bind_rows(
  coef_to_tbl(cv_ridge, "lambda.min", "ridge"),
  coef_to_tbl(cv_ridge, "lambda.1se", "ridge"),
  coef_to_tbl(cv_lasso, "lambda.min", "lasso"),
  coef_to_tbl(cv_lasso, "lambda.1se", "lasso"),
  coef_to_tbl(cv_enet, "lambda.min", "elastic_net"),
  coef_to_tbl(cv_enet, "lambda.1se", "elastic_net")
)

write_csv(
  coef_tbl_all,
  "outputs/tables/regularized_coefficients_all.csv"
)

coef_nonzero_tbl <- coef_tbl_all %>%
  filter(term != "(Intercept)", estimate != 0)

write_csv(
  coef_nonzero_tbl,
  "outputs/tables/regularized_coefficients_nonzero.csv"
)

# Lasso-selected features
lasso_selected_tbl <- coef_tbl_all %>%
  filter(model == "lasso", lambda_choice == "lambda.1se", term != "(Intercept)", estimate != 0) %>%
  arrange(desc(abs(estimate)))

write_csv(
  lasso_selected_tbl,
  "outputs/tables/lasso_selected_features_lambda_1se.csv"
)

# ============================================================
# 10) Coefficient path data
# ============================================================
path_to_long <- function(glmnet_fit, model_name) {
  beta_mat <- as.matrix(glmnet_fit$beta)
  lambda_vals <- glmnet_fit$lambda

  path_df <- as.data.frame(beta_mat)
  path_df$term <- rownames(beta_mat)

  path_long <- path_df %>%
    tidyr::pivot_longer(
      cols = -term,
      names_to = "lambda_index",
      values_to = "coefficient"
    ) %>%
    mutate(
      lambda_index_num = as.integer(gsub("V", "", lambda_index)),
      lambda = lambda_vals[lambda_index_num],
      log_lambda = log(lambda),
      model = model_name
    )

  path_long
}

ridge_path_long <- path_to_long(ridge_fit, "ridge")
lasso_path_long <- path_to_long(lasso_fit, "lasso")
enet_path_long  <- path_to_long(enet_fit, "elastic_net")

write_csv(ridge_path_long, "outputs/tables/ridge_coefficient_paths.csv")
write_csv(lasso_path_long, "outputs/tables/lasso_coefficient_paths.csv")
write_csv(enet_path_long,  "outputs/tables/elastic_net_coefficient_paths.csv")

# ============================================================
# 11) Plots: CV curves
# ============================================================
make_cv_plot <- function(cv_fit, model_name, outfile) {
  cv_df <- tibble(
    lambda = cv_fit$lambda,
    log_lambda = log(cv_fit$lambda),
    cvm = cv_fit$cvm,
    cvsd = cv_fit$cvsd
  )

  p <- ggplot(cv_df, aes(x = log_lambda, y = cvm)) +
    geom_line() +
    geom_point(size = 1.2) +
    geom_vline(xintercept = log(cv_fit$lambda.min), linetype = "dashed") +
    geom_vline(xintercept = log(cv_fit$lambda.1se), linetype = "dotted") +
    theme_minimal() +
    labs(
      title = paste("Cross-Validation Curve:", model_name),
      x = "log(lambda)",
      y = "Mean CV Error"
    )

  ggsave(outfile, plot = p, width = 7, height = 5, dpi = 200)
}

make_cv_plot(cv_ridge, "Ridge", "outputs/figures/cv_curve_ridge.png")
make_cv_plot(cv_lasso, "Lasso", "outputs/figures/cv_curve_lasso.png")
make_cv_plot(cv_enet, "Elastic Net", "outputs/figures/cv_curve_elastic_net.png")

# ============================================================
# 12) Plots: Coefficient paths
# ============================================================
make_path_plot <- function(path_long_df, model_name, outfile) {
  p <- path_long_df %>%
    filter(term %in% feature_names) %>%
    ggplot(aes(x = log_lambda, y = coefficient, group = term)) +
    geom_line(alpha = 0.8) +
    theme_minimal() +
    labs(
      title = paste("Coefficient Paths:", model_name),
      x = "log(lambda)",
      y = "Coefficient"
    )

  ggsave(outfile, plot = p, width = 8, height = 6, dpi = 200)
}

make_path_plot(ridge_path_long, "Ridge", "outputs/figures/coef_path_ridge.png")
make_path_plot(lasso_path_long, "Lasso", "outputs/figures/coef_path_lasso.png")
make_path_plot(enet_path_long, "Elastic Net", "outputs/figures/coef_path_elastic_net.png")

# ============================================================
# 13) Plots: Actual vs predicted for best regularized models
# ============================================================
best_reg_tbl <- regularized_eval_tbl %>%
  arrange(rmse_log)

best_model_name <- best_reg_tbl$model[1]
best_lambda_choice <- best_reg_tbl$lambda_choice[1]

get_best_pred <- function(model_name, lambda_choice) {
  if (model_name == "ridge" && lambda_choice == "lambda.min") return(pred_ridge_min)
  if (model_name == "ridge" && lambda_choice == "lambda.1se") return(pred_ridge_1se)
  if (model_name == "lasso" && lambda_choice == "lambda.min") return(pred_lasso_min)
  if (model_name == "lasso" && lambda_choice == "lambda.1se") return(pred_lasso_1se)
  if (model_name == "elastic_net" && lambda_choice == "lambda.min") return(pred_enet_min)
  if (model_name == "elastic_net" && lambda_choice == "lambda.1se") return(pred_enet_1se)
}

best_pred_log <- get_best_pred(best_model_name, best_lambda_choice)
best_pred_usd <- exp(best_pred_log)

best_pred_df <- test_df %>%
  mutate(
    pred_log_msrp = best_pred_log,
    pred_msrp = best_pred_usd
  )

p_best_log <- ggplot(best_pred_df, aes(x = log_msrp, y = pred_log_msrp)) +
  geom_point(alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  theme_minimal() +
  labs(
    title = paste("Best Regularized Model:", best_model_name, "(", best_lambda_choice, ") - log scale"),
    x = "Actual log(MSRP)",
    y = "Predicted log(MSRP)"
  )

ggsave(
  "outputs/figures/best_regularized_actual_vs_predicted_log.png",
  plot = p_best_log,
  width = 7,
  height = 5,
  dpi = 200
)

p_best_usd <- ggplot(best_pred_df, aes(x = msrp, y = pred_msrp)) +
  geom_point(alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  theme_minimal() +
  labs(
    title = paste("Best Regularized Model:", best_model_name, "(", best_lambda_choice, ") - USD scale"),
    x = "Actual MSRP (USD)",
    y = "Predicted MSRP (USD)"
  )

ggsave(
  "outputs/figures/best_regularized_actual_vs_predicted_usd.png",
  plot = p_best_usd,
  width = 7,
  height = 5,
  dpi = 200
)

# ============================================================
# 14) Combine with OLS benchmark
# ============================================================
ols_eval <- read_csv("outputs/tables/lm_baseline_evaluation.csv", show_col_types = FALSE)

ols_test <- ols_eval %>%
  filter(dataset == "test", scale == "log") %>%
  mutate(
    model = "ols_baseline",
    lambda_choice = NA_character_,
    rmse_log = rmse,
    mae_log = mae,
    r2_log = r_squared
  ) %>%
  select(model, lambda_choice, rmse_log, mae_log, r2_log)

ols_test_usd <- ols_eval %>%
  filter(dataset == "test", scale == "usd") %>%
  transmute(
    rmse_usd = rmse,
    mae_usd = mae,
    r2_usd = r_squared
  )

ols_test <- bind_cols(ols_test, ols_test_usd)

comparison_tbl <- bind_rows(
  ols_test,
  regularized_eval_tbl %>%
    select(model, lambda_choice, rmse_log, mae_log, r2_log, rmse_usd, mae_usd, r2_usd)
) %>%
  arrange(rmse_log)

write_csv(
  comparison_tbl,
  "outputs/tables/model_comparison_ols_ridge_lasso_enet.csv"
)

# Plot comparison by RMSE log
p_compare <- comparison_tbl %>%
  mutate(model_label = ifelse(
    is.na(lambda_choice),
    model,
    paste(model, lambda_choice, sep = " | ")
  )) %>%
  ggplot(aes(x = reorder(model_label, rmse_log), y = rmse_log)) +
  geom_col() +
  coord_flip() +
  theme_minimal() +
  labs(
    title = "Model Comparison: Test RMSE on log(MSRP)",
    x = NULL,
    y = "Test RMSE (log scale)"
  )

ggsave(
  "outputs/figures/model_comparison_test_rmse_log.png",
  plot = p_compare,
  width = 8,
  height = 5,
  dpi = 200
)

# ============================================================
# 15) Plain-English summary
# ============================================================
top_lasso_features <- lasso_selected_tbl %>%
  mutate(line = paste0(term, " : ", round(estimate, 4))) %>%
  pull(line)

summary_lines <- c(
  "Regularized Model Summary",
  "=========================",
  "",
  paste0("Training rows: ", nrow(train_df)),
  paste0("Testing rows: ", nrow(test_df)),
  "",
  "Lambda summary:",
  paste0(" - Ridge lambda.min = ", signif(cv_ridge$lambda.min, 4),
         ", lambda.1se = ", signif(cv_ridge$lambda.1se, 4)),
  paste0(" - Lasso lambda.min = ", signif(cv_lasso$lambda.min, 4),
         ", lambda.1se = ", signif(cv_lasso$lambda.1se, 4)),
  paste0(" - Elastic Net lambda.min = ", signif(cv_enet$lambda.min, 4),
         ", lambda.1se = ", signif(cv_enet$lambda.1se, 4)),
  "",
  "Best regularized model by test RMSE (log scale):",
  paste0(" - ", best_model_name, " using ", best_lambda_choice),
  "",
  "Lasso-selected nonzero features at lambda.1se:",
  if (length(top_lasso_features) > 0) paste0(" - ", top_lasso_features) else " - None",
  "",
  "Interpretation:",
  "Ridge shrinks coefficients while keeping all predictors, making it useful when many engineered features still contain overlapping information.",
  "Lasso performs shrinkage plus variable selection, which can simplify the pricing model.",
  "Elastic Net balances both behaviors.",
  "These models are compared against the baseline OLS benchmark to assess whether regularization improves generalization and model simplicity."
)

writeLines(summary_lines, "outputs/tables/regularized_model_summary.txt")

# ============================================================
# 16) Console output
# ============================================================
cat("\nDONE: 05_regularized_models.R completed successfully.\n\n")
cat("Saved:\n")
cat("- outputs/models/cv_ridge.rds\n")
cat("- outputs/models/cv_lasso.rds\n")
cat("- outputs/models/cv_elastic_net.rds\n")
cat("- outputs/tables/regularized_model_evaluation.csv\n")
cat("- outputs/tables/regularized_lambda_summary.csv\n")
cat("- outputs/tables/regularized_coefficients_all.csv\n")
cat("- outputs/tables/regularized_coefficients_nonzero.csv\n")
cat("- outputs/tables/lasso_selected_features_lambda_1se.csv\n")
cat("- outputs/tables/model_comparison_ols_ridge_lasso_enet.csv\n")
cat("- outputs/tables/regularized_model_summary.txt\n")
cat("- outputs/figures/cv_curve_ridge.png\n")
cat("- outputs/figures/cv_curve_lasso.png\n")
cat("- outputs/figures/cv_curve_elastic_net.png\n")
cat("- outputs/figures/coef_path_ridge.png\n")
cat("- outputs/figures/coef_path_lasso.png\n")
cat("- outputs/figures/coef_path_elastic_net.png\n")
cat("- outputs/figures/model_comparison_test_rmse_log.png\n\n")

cat("Top of model comparison table:\n")
print(comparison_tbl %>% arrange(rmse_log))