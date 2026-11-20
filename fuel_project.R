# fuel_project.R
# Builds a SQLite database of U.S. weekly retail and wholesale (spot) fuel prices
# from public EIA data, creates the SQL views used by the dashboard, and exports
# the dashboard view to CSV for Power BI.
#
# Run from the project folder:  source("fuel_project.R")
# To refresh the data, delete the three .xls files and run the script again.

library(readxl)
library(dplyr)
library(tidyr)
library(DBI)

# ---- 1. Download the EIA workbooks (skipped if already present) ----------------

files <- c(
  "pswrgvwall.xls"  = "https://www.eia.gov/petroleum/gasdiesel/xls/pswrgvwall.xls",  # retail gasoline
  "psw18vwall.xls"  = "https://www.eia.gov/petroleum/gasdiesel/xls/psw18vwall.xls",  # retail diesel
  "spot_weekly.xls" = "https://www.eia.gov/dnav/pet/xls/PET_PRI_SPT_S1_W.xls"        # spot prices
)
for (f in names(files)) {
  if (!file.exists(f)) download.file(files[[f]], f, mode = "wb")
}

# ---- 2. Read one EIA data sheet into long format --------------------------------
# Each sheet has two header rows above the series names, one column per series,
# and dates stored as Excel serial numbers.

read_eia <- function(file, sheet) {
  read_excel(file, sheet = sheet, skip = 2, col_types = "text") |>
    rename(week_date = Date) |>
    pivot_longer(-week_date, names_to = "series", values_to = "price",
                 values_drop_na = TRUE) |>
    mutate(week_date = as.Date(as.numeric(week_date), origin = "1899-12-30"),
           price = as.numeric(price)) |>
    filter(!is.na(price))
}

# ---- 3. Retail prices (weekly, dated Mondays, taxes included) -------------------

gas <- read_eia("pswrgvwall.xls", "Data 3") |> mutate(product = "gasoline")  # regular, all formulations
dsl <- read_eia("psw18vwall.xls", "Data 1") |> mutate(product = "diesel")    # on-highway, all types

retail <- bind_rows(gas, dsl) |>
  mutate(region = sub("^Weekly (.*?) (Regular All Formulations|No 2 Diesel) .*$", "\\1",
                      series, perl = TRUE),
         week_date = as.character(week_date)) |>   # SQLite has no date type; store ISO text
  select(week_date, region, product, price)

# ---- 4. Spot (wholesale) prices (weekly averages, dated Fridays) ----------------

spot <- bind_rows(
  read_eia("spot_weekly.xls", "Data 2") |> mutate(product = "gasoline"),   # NY Harbor, Gulf Coast
  read_eia("spot_weekly.xls", "Data 3") |> mutate(product = "gasoline"),   # Los Angeles
  read_eia("spot_weekly.xls", "Data 5") |> mutate(product = "diesel")      # all three hubs
) |>
  mutate(hub = case_when(grepl("New York Harbor", series) ~ "New York Harbor",
                         grepl("Gulf Coast", series)      ~ "Gulf Coast",
                         grepl("Los Angeles", series)     ~ "Los Angeles"),
         week_date = as.character(week_date)) |>
  select(week_date, hub, product, price)

# ---- 5. Lookup table: benchmark spot hub for each region ------------------------
# A simplification. The U.S. average is benchmarked to the Gulf Coast; Rocky
# Mountain is left unmapped because none of the three hubs fits it well.

regions <- data.frame(
  region        = c("U.S.",       "East Coast",      "Midwest",    "Gulf Coast", "West Coast"),
  benchmark_hub = c("Gulf Coast", "New York Harbor", "Gulf Coast", "Gulf Coast", "Los Angeles")
)

# ---- 6. Write the tables and create the views -----------------------------------

run_sql_file <- function(con, file) {
  sql   <- paste(readLines(file), collapse = "\n")
  sql   <- gsub("--[^\n]*", "", sql)                 # remove comments
  stmts <- trimws(strsplit(sql, ";")[[1]])
  for (s in stmts[nzchar(stmts)]) dbExecute(con, s)
}

con <- dbConnect(RSQLite::SQLite(), "fuel.sqlite")
dbWriteTable(con, "retail_prices", retail,  overwrite = TRUE)
dbWriteTable(con, "spot_prices",   spot,    overwrite = TRUE)
dbWriteTable(con, "regions",       regions, overwrite = TRUE)
run_sql_file(con, "views.sql")

# ---- 7. Checks and export for Power BI ------------------------------------------

print(dbGetQuery(con, "
  SELECT product, COUNT(*) AS n_rows, COUNT(DISTINCT region) AS n_regions,
         MIN(week_date) AS first_week, MAX(week_date) AS last_week
  FROM retail_prices GROUP BY product"))
print(dbGetQuery(con, "SELECT * FROM v_dashboard WHERE is_latest_week = 1"))

write.csv(dbGetQuery(con, "SELECT * FROM v_dashboard ORDER BY week_date DESC, product, region"),
          "v_dashboard.csv", row.names = FALSE, na = "")
dbDisconnect(con)
