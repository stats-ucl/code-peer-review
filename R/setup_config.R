# configuration functions

#' Install required packages
#'
#' @export
install_required_packages <- function() {
  required_packages <- c("gh", "dplyr", "readr", "purrr", "glue", "base64enc", 
                         "ggplot2", "lubridate", "scales")
  
  missing_packages <- setdiff(required_packages, rownames(installed.packages()))
  
  if (length(missing_packages) > 0) {
    cat("Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
    install.packages(missing_packages)
  } else {
    cat("All required packages are already installed.\n")
  }
}

#' Set up GitHub token
#'
#' @export
setup_github_token <- function() {
  cat("GitHub Token Setup\n")
  cat("==================\n")
  cat("You need a GitHub Personal Access Token to use these scripts.\n\n")
  cat("To create a token:\n")
  cat("1. Go to https://github.com/settings/tokens\n")
  cat("2. Click 'Generate new token (classic)'\n")
  cat("3. Give it a descriptive name\n")
  cat("4. Select these scopes:\n")
  cat("   - repo (Full control of private repositories)\n")
  cat("   - admin:org (Full control of orgs and teams)\n")
  cat("   - user (Update ALL user data)\n")
  cat("5. Copy the generated token\n\n")
  
  # Check if token is already set
  current_token <- Sys.getenv("GITHUB_TOKEN")
  if (current_token != "") {
    cat("GitHub token is already set in environment.\n")
    cat("Current token starts with:", substr(current_token, 1, 8), "...\n")
    
    response <- readline("Do you want to update it? (y/n): ")
    if (tolower(response) != "y") {
      return(invisible())
    }
  }
  
  cat("You can set your token in two ways:\n")
  cat("1. Create a .Renviron file in your project directory\n")
  cat("2. Set it temporarily for this session\n\n")
  
  method <- readline("Choose method (1 or 2): ")
  
  if (method == "1") {
    ##NG: what about instead
    # usethis::create_github_token()
    # gitcreds::gitcreds_set()
    # or usethis::edit_r_environ(scope = "project") and adding GITHUB_TOKEN={token}?
    
    token <- readline("Enter your GitHub token: ")
    renviron_content <- glue("GITHUB_TOKEN={token}")
    write_file(renviron_content, ".Renviron")
    cat("Token saved to .Renviron file.\n")
    cat("IMPORTANT: Restart R session for changes to take effect!\n")
    cat("SECURITY: Add .Renviron to your .gitignore file!\n")
  } else if (method == "2") {
    token <- readline("Enter your GitHub token: ")
    Sys.setenv(GITHUB_TOKEN = token)
    cat("Token set for this session.\n")
    cat("NOTE: You'll need to set this again in new R sessions.\n")
  }
}

#' Create sample student list CSV file
#' 
#'  | student_id | github_username | ucl_email | name |
#'  | :--- | :--- | :--- | :--- |
#'  | 12345 | student1_github | student1@ucl.ac.uk | Alice Smith |
#'  | 12346 | student2_github | student2@ucl.ac.uk | Bob Jones |
#'  | 12347 | student3_github | student3@ucl.ac.uk | Carol White |
#'  | 12348 | student4_github | student4@ucl.ac.uk | David Brown |
#'  | 12349 | student5_github | student5@ucl.ac.uk | Eve Davis |
#'
#' @importFrom glue glue
#' @importFrom readr write_file
#' @importFrom dplyr tibble
#' 
#' @export
create_sample_student_list <- function(filename = "student_list.csv") {
  if (file.exists(filename)) {
    response <- readline(glue("{filename} already exists. Overwrite? (y/n): "))
    if (tolower(response) != "y") {
      return(invisible())
    }
  }
  
  sample_data <- tibble(
    student_id = c("12345", "12346", "12347", "12348", "12349"),
    github_username = c("student1_github", "student2_github", "student3_github", 
                        "student4_github", "student5_github"),
    ucl_email = c("student1@ucl.ac.uk", "student2@ucl.ac.uk", "student3@ucl.ac.uk",
                  "student4@ucl.ac.uk", "student5@ucl.ac.uk"),
    name = c("Alice Smith", "Bob Jones", "Carol White", "David Brown", "Eve Davis")
  )
  
  readr::write_csv(sample_data, filename)
  cat(glue::glue("Sample student list created: {filename}\n"))
  cat("Please edit this file with your actual student data.\n")
  cat("Required columns: student_id, github_username, ucl_email, name\n")
}

#' Create directory structure
#' 
#' @importFrom glue glue
#' @importFrom readr write_file
#'
#' @export
create_directory_structure <- function() {
  dirs <- c("submissions", "email_templates", "progress_reports", "reminders")
  
  for (dir in dirs) {
    if (!dir.exists(dir)) {
      dir.create(dir, recursive = TRUE)
      cat(glue::glue("Created directory: {dir}\n"))
    }
  }
  
  # Create sample submission folders
  sample_students <- c("12345", "12346", "12347", "12348", "12349")
  
  for (student_id in sample_students) {
    student_dir <- file.path("submissions", student_id)
    
    if (!dir.exists(student_dir)) {
      dir.create(student_dir, recursive = TRUE)
      
      # Create a sample R file
      sample_code <- '# Sample R code for peer review
# Student ID: {student_id}

# Load required libraries
library(ggplot2)

# Read data
data <- mtcars

# Create visualization
plot <- ggplot(data, aes(x = mpg, y = wt)) +
  geom_point() +
  labs(title = "Miles per Gallon vs Weight",
       x = "Miles per Gallon",
       y = "Weight")

print(plot)

# Basic analysis
summary(data$mpg)
'
      readr::write_file(glue::glue(sample_code), file.path(student_dir, "analysis.R"))
    }
  }
  
  cat("Sample submission structure created in submissions/ directory\n")
}

#' Validate configuration
#'
#' @importFrom readr read_csv
#' @export
validate_configuration <- function() {
  cat("Configuration Validation\n")
  cat("========================\n")
  
  issues <- c()
  
  # Check GitHub token
  token <- Sys.getenv("GITHUB_TOKEN")
  if (token == "") {
    issues <- c(issues, "❌ GitHub token not set")
  } else {
    cat("✅ GitHub token is set\n")
  }
  
  # Check student list file
  if (file.exists("student_list.csv")) {
    students <- try(readr::read_csv("student_list.csv", show_col_types = FALSE), silent = TRUE)
    
    if (inherits(students, "try-error")) {
      issues <- c(issues, "❌ Cannot read student_list.csv")
    } else {
      required_cols <- c("student_id", "github_username", "ucl_email", "name")
      missing_cols <- setdiff(required_cols, names(students))
    
      if (length(missing_cols) > 0) {
        issues <- c(issues, glue("❌ Missing columns in student_list.csv: {paste(missing_cols, collapse=', ')}"))
      } else {
        cat(glue("✅ Student list file valid ({nrow(students)} students)\n"))
      }
    }
  } else {
    issues <- c(issues, "❌ student_list.csv not found")
  }
  
  # Check submissions directory
  if (dir.exists("submissions")) {
    n_folders <- length(list.dirs("submissions", recursive = FALSE))
    if (n_folders > 0) {
      cat(glue("✅ Submissions directory exists ({n_folders} student folders)\n"))
    } else {
      issues <- c(issues, "⚠️  Submissions directory is empty")
    }
  } else {
    issues <- c(issues, "❌ Submissions directory not found")
  }
  
  # Check required R files
  required_files <- c("github_functions.R", "file_management.R")
  for (file in required_files) {
    if (file.exists(file)) {
      cat(glue("✅ {file} found\n"))
    } else {
      issues <- c(issues, glue("❌ {file} not found"))
    }
  }
  
  if (length(issues) > 0) {
    cat("\nIssues found:\n")
    for (issue in issues) {
      cat(issue, "\n")
    }
    cat("\nPlease resolve these issues before running the main script.\n")
    return(FALSE)
  } else {
    cat("\n🎉 Configuration is valid! You're ready to run the main script.\n")
    return(TRUE)
  }
}

#' Create gitignore file
#'
#' @export
create_gitignore <- function() {
  ##NG: could the output files be saved in their own folder and
  # then ignore that?
  
  gitignore_content <- '# R files
\\.Rhistory
\\.RData
\\.Rapp.history

# Environment files (contains sensitive tokens)
\\.Renviron
\\.env

# Student data (privacy)
student_list\\.csv
submissions/
progress_reports/
email_templates/
reminders/

# Output files
*\\.csv
*\\.png
*\\.pdf

# Temporary files
*\\.tmp
*\\.log
'
  
  if (!file.exists(".gitignore")) {
    write_file(gitignore_content, ".gitignore")
    cat("Created .gitignore file\n")
  } else {
    cat(".gitignore already exists\n")
  }
}

#' Main set-up function
#'
#' @export
run_setup <- function() {
  cat("GitHub Peer Review System Setup\n")
  cat("===============================\n\n")
  
  # Install packages
  cat("1. Installing required packages...\n")
  install_required_packages()
  cat("\n")
  
  # Setup GitHub token
  cat("2. Setting up GitHub authentication...\n")
  setup_github_token()
  cat("\n")
  
  # Create directory structure
  cat("3. Creating directory structure...\n")
  create_directory_structure()
  cat("\n")
  
  # Create sample files
  cat("4. Creating sample configuration files...\n")
  create_sample_student_list()
  create_gitignore()
  cat("\n")
  
  # Validate configuration
  cat("5. Validating configuration...\n")
  is_valid <- validate_configuration()
  cat("\n")
  
  if (is_valid) {
    cat("Setup complete! Next steps:\n")
    cat("1. Edit student_list.csv with your actual student data\n")
    cat("2. Place student submission files in submissions/[student_id]/ folders\n")
    cat("3. Update configuration variables in the main script\n")
    cat("4. Run the main automation script\n")
  } else {
    cat("Setup incomplete. Please resolve the issues above.\n")
  }
}

#' Configuration helper
#'
#' @export
show_configuration_template <- function() {
  cat("Configuration Template\n")
  cat("======================\n")
  cat("Add these lines to the top of your main script:\n\n")
  
  template <- '# Configuration
GITHUB_TOKEN <- Sys.getenv("GITHUB_TOKEN")
ORG_NAME <- "UCL-StatSci-STAT001-2025"      # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"            # Current assignment identifier
LOCAL_SUBMISSIONS_PATH <- "submissions/"     # Path to student submission folders

# Customize these as needed:
REVIEWS_PER_STUDENT <- 2                     # How many reviews each student receives
DEADLINE_DATE <- "2025-04-15"               # Review deadline
COURSE_NAME <- "STAT001"                     # Course identifier
'
  
  cat(template)
}

#' Quick test function
#'
#' @export
test_github_connection <- function() {
  tryCatch({
    library(gh)
    user_info <- gh("GET /user")
    cat(glue("✅ Successfully connected to GitHub as: {user_info$login}\n"))
    cat(glue("Profile: {user_info$html_url}\n"))
    
    # Test organization access if provided
    org_name <- readline("Enter your organization name to test access (or press Enter to skip): ")
    if (org_name != "") {
      org_info <- gh("GET /orgs/{org}", org = org_name)
      cat(glue("✅ Organization access confirmed: {org_info$login}\n"))
    }
    
  }, error = function(e) {
    cat("❌ GitHub connection failed:\n")
    cat(e$message, "\n")
    cat("Please check your GitHub token setup.\n")
  })
}
