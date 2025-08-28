# GitHub Code Peer Review Automation Script
# Main orchestration script for setting up repositories and peer review assignments

# Load required libraries
library(gh)
library(dplyr)
library(readr)
library(purrr)
library(glue)
library(base64enc)

# Source helper functions
source("github_functions.R")
source("file_management.R")

# Configuration
GITHUB_TOKEN <- Sys.getenv("GITHUB_TOKEN")  # Set your GitHub token as environment variable
ORG_NAME <- "UCL-StatSci-STAT0001-2025"      # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"            # Current assignment identifier
LOCAL_SUBMISSIONS_PATH <- "submissions/"     # Path to local student submission folders

# Check GitHub authentication
check_github_auth()

# Read student information
cat("Reading student data...\n")
students <- read_csv("student_list.csv") # Should contain: student_id, github_username, ucl_email, name

# Validate student data
validate_student_data(students)

# Create repositories for all students
cat("Creating repositories...\n")
repo_results <- students %>%
  mutate(
    repo_name = glue("student-{student_id}-{ASSIGNMENT_NAME}"),
    repo_created = map2_lgl(repo_name, github_username, ~create_student_repo(.x, .y, ORG_NAME))
  )

# Set up repository structure (branches, templates, etc.)
cat("Setting up repository structure...\n")
repo_results <- repo_results %>%
  mutate(
    structure_setup = map2_lgl(repo_name, student_id, ~setup_repo_structure(.x, ORG_NAME))
  )

# Upload student files
cat("Uploading student submissions...\n")
repo_results <- repo_results %>%
  mutate(
    files_uploaded = map2_lgl(repo_name, student_id, ~upload_student_files(.x, .y, ORG_NAME, LOCAL_SUBMISSIONS_PATH))
  )

# Assign peer reviewers
cat("Assigning peer reviewers...\n")
reviewer_assignments <- assign_peer_reviewers(students)

# Set repository permissions for reviewers
cat("Setting repository permissions...\n")
permission_results <- map2_dfr(
  repo_results$repo_name, 
  repo_results$student_id,
  ~set_reviewer_permissions(.x, .y, reviewer_assignments, ORG_NAME)
)

# Generate distribution URLs and information
cat("Generating distribution information...\n")
distribution_info <- generate_distribution_info(repo_results, reviewer_assignments, ORG_NAME)

# Save results
cat("Saving results...\n")
write_csv(distribution_info$student_links, "student_repo_links.csv")
write_csv(distribution_info$reviewer_assignments, "reviewer_assignments.csv")
write_csv(distribution_info$teacher_summary, "teacher_summary.csv")

# Generate email templates
cat("Generating email templates...\n")
generate_email_templates(distribution_info, "email_templates/")

# Print summary
cat("\n=== SETUP COMPLETE ===\n")
cat(glue("Repositories created: {sum(repo_results$repo_created)}/{nrow(repo_results)}\n"))
cat(glue("Files uploaded: {sum(repo_results$files_uploaded)}/{nrow(repo_results)}\n"))
cat(glue("Total reviewer assignments: {nrow(reviewer_assignments)}\n"))
cat("\nCheck the following files for distribution:\n")
cat("- student_repo_links.csv: URLs for each student\n")
cat("- reviewer_assignments.csv: Who reviews whom\n")
cat("- email_templates/: Email templates for students and reviewers\n")

cat("\nNext steps:\n")
cat("1. Review the generated files\n")
cat("2. Send emails to students using the templates\n")
cat("3. Monitor repository activity\n")
cat("4. Use 'monitor_progress.R' to track completion\n")