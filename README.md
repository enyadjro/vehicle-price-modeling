Interpretable Modeling of New Vehicle Prices

This project develops an end-to-end interpretable regression pipeline to model new vehicle prices using automotive characteristics such as performance, fuel economy, drivetrain, body type, and vehicle size.

Rather than focusing only on predictive accuracy, the project emphasizes economic interpretability and model stability, combining multicollinearity diagnostics with modern regularization methods (Ridge, Lasso, and Elastic Net).

The goal is to understand what drives vehicle market value and demonstrate how interpretable models can support pricing strategy, product positioning, and competitive benchmarking.

Problem Overview

Vehicle pricing reflects a combination of:

engineering characteristics

performance capability

vehicle size and weight

drivetrain configuration

body style segmentation

Manufacturers must balance these factors when positioning vehicles in the market.

This project models vehicle prices using regression techniques to answer two key questions:

Which vehicle attributes drive price the most?

How do we build stable, interpretable models when predictors are highly correlated?

Data

The dataset contains characteristics of 2004 model-year vehicles.

Typical variables include:

engine size

horsepower

vehicle weight

fuel economy

drivetrain (RWD / AWD)

vehicle body type

wheelbase and vehicle dimensions

dealer cost and retail price

Target variable:

MSRP (Manufacturer Suggested Retail Price)

Because vehicle prices are right-skewed, the modeling target uses:

log(MSRP)
Project Workflow

The project follows a structured modeling pipeline:

EDA → Feature Engineering → Multicollinearity Diagnostics → 
OLS Baseline → Regularized Models → Model Interpretation

Key stages include:

Exploratory Data Analysis

Initial analysis examines the distribution of vehicle prices and relationships between vehicle characteristics and MSRP.

Feature Engineering

Economically meaningful features are created, including:

power-to-weight ratio

average fuel efficiency

vehicle footprint

drivetrain indicators

vehicle segment indicators

Log transformations are applied to stabilize skewed variables.

Multicollinearity Diagnostics

Vehicle design variables are often strongly correlated.

To diagnose this, the project evaluates:

pairwise correlations

variance inflation factors (VIF)

condition indices

This helps identify instability in ordinary least squares models.

Baseline Model: Ordinary Least Squares

An initial OLS regression model provides a benchmark for comparison.

Actual vs Predicted Prices

Residual Diagnostics

These diagnostics highlight why multicollinearity can affect coefficient stability.

Regularized Regression Models

To address multicollinearity and improve generalization, the project compares:

Ridge Regression

Lasso Regression

Elastic Net

These models shrink or select coefficients to produce more stable predictions.

Model Comparison

Elastic Net achieves the best balance between predictive performance and interpretability.

Elastic Net Model Performance

Predicted vs Actual vehicle prices using the best regularized model:

The model captures the majority of variation in vehicle prices while maintaining interpretable coefficients.

Key Drivers of Vehicle Price

The Elastic Net model identifies the most influential features affecting vehicle prices.

Major drivers include:

Vehicle weight

Vehicle footprint

Sports car classification

Rear-wheel drive

Engine size

These results reflect real automotive market dynamics:

heavier vehicles often indicate larger platforms or luxury features

sports cars command premium pricing

drivetrain and performance characteristics affect positioning

Repository Structure
vehicle-price-modeling
│
├── data
│   └── raw dataset
│
├── scripts
│   ├── 01_data_exploration.R
│   ├── 02_multicollinearity_diagnostics.R
│   ├── 03_feature_engineering.R
│   ├── 04_linear_model_baseline.R
│   ├── 05_regularized_models.R
│   └── 06_model_interpretation.R
│
└── key result figures
Business Applications

This analysis demonstrates how interpretable models can support:

Pricing Strategy

Understanding how vehicle attributes contribute to price helps guide MSRP decisions.

Product Positioning

Manufacturers can identify which design features most strongly influence perceived value.

Competitive Benchmarking

Automakers can compare vehicles with similar characteristics to identify pricing gaps.

Tools Used
R
ggplot2
dplyr
glmnet
readr
