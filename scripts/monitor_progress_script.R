# Progress Monitoring Script
# Track completion of peer reviews and generate reports

# Load required libraries
library(gh)
library(dplyr)
library(readr)
library(purrr)
library(glue)
library(ggplot2)
library(lubridate)

# Configuration
GITHUB_TOKEN <- Sys.getenv("GITHUB_TOKEN")
ORG_NAME <- "UCL-StatSci-STAT001-2025"      # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"

# Source helper functions
source("github_functions.R")

# Check authentication
check_github_auth()

# Read existing data
students <- read_csv("student_list.csv")
reviewer_assignments <- read_csv("reviewer_assignments.csv")

# Get all repository names for this assignment
repo_names <- students %>%
  mutate(repo_name = glue("student-{student_id}-{ASSIGNMENT_NAME}")) %>%
  pull(repo_name)

# Run the progress check
if (interactive()) {
  report <- run_progress_check()
}