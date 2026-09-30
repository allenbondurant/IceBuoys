required <- c("shiny", "bslib", "dplyr", "readr", "ggplot2", "lubridate", "scales")
missing <- setdiff(required, rownames(installed.packages()))
if (length(missing) > 0) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}
