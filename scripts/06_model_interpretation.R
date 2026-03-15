# ============================================================
# Project: Interpretable Modeling of New Vehicle Prices
# Script: 06_model_interpretation.R
# Purpose: Interpret key drivers of vehicle prices from the
#          regularized models
# ============================================================

library(dplyr)
library(ggplot2)
library(readr)

dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables", showWarnings = FALSE, recursive = TRUE)

# ============================================================
# Load coefficients
# ============================================================
coef_all <- read_csv(
  "outputs/tables/regularized_coefficients_all.csv",
  show_col_types = FALSE
)

coef_nonzero <- read_csv(
  "outputs/tables/regularized_coefficients_nonzero.csv",
  show_col_types = FALSE
)

# ============================================================
# Elastic Net coefficients at lambda.min
# ============================================================
enet_coef <- coef_nonzero %>%
  filter(
    model == "elastic_net",
    lambda_choice == "lambda.min",
    term != "(Intercept)"
  ) %>%
  mutate(
    abs_coef = abs(estimate),
    effect_direction = ifelse(estimate >= 0, "Positive", "Negative")
  )

# ============================================================
# Full ranked importance table
# ============================================================
importance <- enet_coef %>%
  arrange(desc(abs_coef))

write_csv(
  importance,
  "outputs/tables/elastic_net_feature_importance.csv"
)

# ============================================================
# Plot dataset: top 10 drivers by absolute importance
# ============================================================
plot_df <- importance %>%
  slice_head(n = 10) %>%
  arrange(abs_coef) %>%
  mutate(term = reorder(term, abs_coef))

# ============================================================
# Plot: Key drivers of vehicle price
# ============================================================
p <- ggplot(plot_df, aes(x = term, y = estimate, fill = effect_direction)) +
  geom_col() +
  coord_flip() +
  scale_fill_manual(
    values = c("Negative" = "red3", "Positive" = "steelblue")
  ) +
  labs(
    title = "Top 10 Drivers of Vehicle Price (Elastic Net)",
    x = "",
    y = "Coefficient (log MSRP)",
    fill = "Effect"
  ) +
  theme_minimal()

ggsave(
  "outputs/figures/elastic_net_feature_importance.png",
  plot = p,
  width = 9,
  height = 6,
  dpi = 300
)

# ============================================================
# Plain-English interpretation file
# ============================================================
top_lines <- importance %>%
  mutate(line = paste0(term, " : ", round(estimate, 4))) %>%
  pull(line)

summary_lines <- c(
  "Elastic Net Feature Interpretation",
  "=================================",
  "",
  "Model used: elastic_net at lambda.min",
  "",
  "Top drivers by absolute coefficient:",
  paste0(" - ", head(top_lines, 12)),
  "",
  "Interpretation notes:",
  "Positive coefficients are associated with higher predicted vehicle prices.",
  "Negative coefficients are associated with lower predicted vehicle prices, holding the other engineered predictors fixed.",
  "Because the target is log(MSRP), coefficients approximately reflect proportional effects rather than raw dollar effects.",
  "The plot displays the top 10 drivers ranked by absolute coefficient magnitude while preserving sign."
)

writeLines(
  summary_lines,
  "outputs/tables/elastic_net_feature_interpretation.txt"
)

# ============================================================
# Console summary
# ============================================================
cat("\nTop price drivers:\n")
print(head(importance, 10))

cat("\nSaved:\n")
cat("- outputs/figures/elastic_net_feature_importance.png\n")
cat("- outputs/tables/elastic_net_feature_importance.csv\n")
cat("- outputs/tables/elastic_net_feature_interpretation.txt\n")