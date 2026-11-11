# Configuration and Setup Functions

#' Install required packages
#'
#' Checks whether required packages for `codeinput` are installed and installs
#' any missing packages.
#'
#' @return Logical `TRUE` invisibly if all packages are available.
#' @export
install_required_packages <- function() {
  required_packages <- c(
    "gh", "dplyr", "readr", "purrr", "glue", "base64enc",
    "ggplot2", "lubridate", "scales", "tidyr", "usethis", "gitcreds"
  )

  missing_packages <- required_packages[
    !purrr::map_lgl(required_packages, requireNamespace, quietly = TRUE)
  ]

  if (length(missing_packages) > 0) {
    cat("Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
    utils::install.packages(missing_packages)
  } else {
    cat("All required packages are already installed.\n")
  }

  invisible(TRUE)
}

#' Set up GitHub token
#'
#' Guides the user through creating and storing a GitHub Personal Access Token
#' (PAT) using `usethis::create_github_token()` and `gitcreds::gitcreds_set()`,
#' or via a project `.Renviron` file using `usethis::edit_r_environ()`.
#'
#' @return Invisibly returns `NULL`.
#' @export
setup_github_token <- function() {
  cat("GitHub Token Setup\n")
  cat("==================\n")
  cat("You need a GitHub Personal Access Token (PAT) with scopes:\n")
  cat("  - repo (Full control of private repositories)\n")
  cat("  - admin:org (Full control of organizations and teams)\n")
  cat("  - user (Update user data)\n\n")

  if (file.exists(".Renviron")) {
    readRenviron(".Renviron")
  }

  whoami <- tryCatch(gh::gh_whoami(), error = function(e) NULL)
  if (!is.null(whoami) && !is.null(whoami$login)) {
    cat(glue::glue("GitHub token is already configured for user: {whoami$login}"), "\n")
    if (!interactive()) {
      return(invisible(NULL))
    }
    response <- readline("Do you want to update your GitHub credentials? (y/n): ")
    if (tolower(trimws(response)) != "y") {
      return(invisible(NULL))
    }
  }

  if (!interactive()) {
    cat("Non-interactive session: run `usethis::create_github_token()` and `gitcreds::gitcreds_set()`,\n")
    cat("or set the GITHUB_TOKEN environment variable.\n")
    return(invisible(NULL))
  }

  cat("Choose how to configure your GitHub token:\n")
  cat("1. Use gitcreds credential store (Recommended: usethis::create_github_token() + gitcreds::gitcreds_set())\n")
  cat("2. Save token to project .Renviron file\n\n")

  method <- trimws(readline("Choose method (1 or 2): "))

  if (method == "1") {
    create_new <- trimws(readline("Open browser to create a new token on GitHub first? (y/n): "))
    if (tolower(create_new) == "y") {
      usethis::create_github_token(
        scopes = c("repo", "admin:org", "user"),
        description = "codeinput peer review automation"
      )
    }
    cat("Now enter your token in the gitcreds prompt:\n")
    gitcreds::gitcreds_set()
    cat("Token stored in gitcreds credential store.\n")
  } else if (method == "2") {
    token <- trimws(readline("Enter your GitHub token (or press Enter to open .Renviron in editor): "))
    if (nzchar(token)) {
      readr::write_file(paste0("GITHUB_TOKEN=", token, "\n"), ".Renviron")
      Sys.setenv(GITHUB_TOKEN = token)
      readRenviron(".Renviron")
      cat("Token saved to .Renviron and loaded into the current R session.\n")
    } else {
      cat("Opening project .Renviron. Add a line with:\n")
      cat("GITHUB_TOKEN=your_token_here\n")
      usethis::edit_r_environ(scope = "project")
      if (file.exists(".Renviron")) {
        readRenviron(".Renviron")
      }
    }
  } else {
    cat("Skipping token configuration.\n")
  }

  invisible(NULL)
}

#' Create sample student list CSV file
#'
#' Generates a template `student_list.csv` file with columns:
#' `student_id`, `github_username`, `ucl_email`, and `name`.
#'
#' @param filename Path to the CSV file to create. Defaults to `"student_list.csv"`.
#' @param overwrite Logical; whether to overwrite an existing file without prompting.
#'
#' @return Invisibly returns the path to `filename`.
#' @importFrom glue glue
#' @importFrom readr write_csv
#' @importFrom dplyr tibble
#' @export
create_sample_student_list <- function(filename = "student_list.csv", overwrite = FALSE) {
  if (file.exists(filename) && !overwrite) {
    if (interactive()) {
      response <- readline(glue::glue("{filename} already exists. Overwrite? (y/n): "))
      if (tolower(trimws(response)) != "y") {
        return(invisible(filename))
      }
    } else {
      cat(glue::glue("{filename} already exists; skipping."), "\n")
      return(invisible(filename))
    }
  }

  sample_data <- dplyr::tibble(
    student_id = c("12345", "12346", "12347", "12348", "12349"),
    github_username = c(
      "student1_github", "student2_github", "student3_github",
      "student4_github", "student5_github"
    ),
    ucl_email = c(
      "student1@ucl.ac.uk", "student2@ucl.ac.uk", "student3@ucl.ac.uk",
      "student4@ucl.ac.uk", "student5@ucl.ac.uk"
    ),
    name = c("Alice Smith", "Bob Jones", "Carol White", "David Brown", "Eve Davis")
  )

  readr::write_csv(sample_data, filename)
  cat(glue::glue("Sample student list created: {filename}"), "\n")
  cat("Please edit this file with your actual student data.\n")
  cat("Required columns: student_id, github_username, ucl_email, name\n")

  invisible(filename)
}

#' Create directory structure
#'
#' Creates the `submissions/` folder and the consolidated `output/` directory
#' (including `email_templates`, `progress_reports`, and `reminders` subfolders).
#'
#' @param submissions_dir Path to the local student submissions folder. Defaults to `"submissions"`.
#' @param output_dir Path to the output directory for generated files. Defaults to `"output"`.
#' @param create_samples Logical; whether to populate sample student submission folders. Defaults to `TRUE`.
#'
#' @return Invisibly returns a character vector of created directories.
#' @importFrom glue glue
#' @importFrom readr write_file
#' @export
create_directory_structure <- function(submissions_dir = "submissions",
                                       output_dir = "output",
                                       create_samples = TRUE) {
  dirs <- c(
    submissions_dir,
    output_dir,
    file.path(output_dir, "email_templates"),
    file.path(output_dir, "progress_reports"),
    file.path(output_dir, "reminders")
  )

  for (dir in dirs) {
    if (!dir.exists(dir)) {
      dir.create(dir, recursive = TRUE)
      cat(glue::glue("Created directory: {dir}"), "\n")
    }
  }

  if (create_samples) {
    sample_students <- c("12345", "12346", "12347", "12348", "12349")

    for (student_id in sample_students) {
      student_dir <- file.path(submissions_dir, student_id)

      if (!dir.exists(student_dir)) {
        dir.create(student_dir, recursive = TRUE)

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

    cat(glue::glue("Sample submission structure created in {submissions_dir}/ directory"), "\n")
  }

  invisible(dirs)
}

#' Create starter workflow scripts
#'
#' Generates starter `main_automation_script.R` and `monitor_progress_script.R`
#' files in the working directory that load `library(codeinput)` and call
#' `run_automation()` and `run_progress_check()`.
#'
#' @param overwrite Logical; whether to overwrite existing scripts. Defaults to `FALSE`.
#'
#' @return Invisibly returns the created script filenames.
#' @export
create_starter_scripts <- function(overwrite = FALSE) {
  main_script <- '# GitHub Code Peer Review - Main Automation Script
library(codeinput)

# Configuration
ORG_NAME <- "UCL-StatSci-STAT0001-2025"   # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"         # Current assignment identifier
SUBMISSIONS_PATH <- "submissions"         # Path to student submission folders
STUDENT_LIST_PATH <- "student_list.csv"   # Path to student list CSV
OUTPUT_DIR <- "output"                    # Directory for generated outputs
REVIEWS_PER_STUDENT <- 2                  # Number of peer reviews per student
DEADLINE <- "2025-04-15"                  # Peer review deadline
INSTRUCTOR_NAME <- "Course Instructor"    # Name shown in email templates

# Run full peer review setup and automation
results <- run_automation(
  org_name = ORG_NAME,
  assignment_name = ASSIGNMENT_NAME,
  student_list_path = STUDENT_LIST_PATH,
  submissions_path = SUBMISSIONS_PATH,
  output_dir = OUTPUT_DIR,
  reviews_per_student = REVIEWS_PER_STUDENT,
  deadline = DEADLINE,
  instructor_name = INSTRUCTOR_NAME
)
'

  monitor_script <- '# GitHub Code Peer Review - Progress Monitoring Script
library(codeinput)

# Configuration
ORG_NAME <- "UCL-StatSci-STAT0001-2025"   # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"         # Current assignment identifier
STUDENT_LIST_PATH <- "student_list.csv"   # Path to student list CSV
OUTPUT_DIR <- "output"                    # Directory containing reviewer_assignments.csv
DEADLINE <- "2025-04-15"                  # Peer review deadline for reminder emails
INSTRUCTOR_NAME <- "Course Instructor"    # Name shown in reminder emails

# Run progress check and generate reports/reminders
report <- run_progress_check(
  org_name = ORG_NAME,
  assignment_name = ASSIGNMENT_NAME,
  student_list_path = STUDENT_LIST_PATH,
  output_dir = OUTPUT_DIR,
  deadline = DEADLINE,
  instructor_name = INSTRUCTOR_NAME
)
'

  scripts <- list(
    "main_automation_script.R" = main_script,
    "monitor_progress_script.R" = monitor_script
  )

  for (fname in names(scripts)) {
    if (!file.exists(fname) || overwrite) {
      readr::write_file(scripts[[fname]], fname)
      cat(glue::glue("Created starter script: {fname}"), "\n")
    } else {
      cat(glue::glue("{fname} already exists; skipping."), "\n")
    }
  }

  invisible(names(scripts))
}

#' Validate configuration
#'
#' Validates that GitHub authentication, `student_list.csv`, and the
#' `submissions/` directory are properly configured.
#'
#' @param student_list_path Path to the student list CSV file. Defaults to `"student_list.csv"`.
#' @param submissions_path Path to the submissions folder. Defaults to `"submissions"`.
#'
#' @return Logical `TRUE` if configuration is valid, `FALSE` otherwise.
#' @importFrom readr read_csv
#' @export
validate_configuration <- function(student_list_path = "student_list.csv",
                                   submissions_path = "submissions") {
  cat("Configuration Validation\n")
  cat("========================\n")

  issues <- character()

  if (file.exists(".Renviron")) {
    readRenviron(".Renviron")
  }

  # Check GitHub authentication via gh_whoami() or environment variables
  whoami <- tryCatch(gh::gh_whoami(), error = function(e) NULL)
  has_token <- (!is.null(whoami) && (!is.null(whoami$login) || !is.null(whoami$token))) ||
    nzchar(Sys.getenv("GITHUB_TOKEN")) ||
    nzchar(Sys.getenv("GITHUB_PAT"))

  if (!has_token) {
    issues <- c(issues, "\u274c GitHub token not configured (run `setup_github_token()`)")
  } else if (!is.null(whoami$login)) {
    cat(glue::glue("\u2705 GitHub authenticated as: {whoami$login}"), "\n")
  } else {
    cat("\u2705 GitHub token is set\n")
  }

  # Check student list file
  if (file.exists(student_list_path)) {
    students <- tryCatch(
      readr::read_csv(
        student_list_path,
        col_types = readr::cols(.default = readr::col_character()),
        show_col_types = FALSE
      ),
      error = function(e) e
    )

    if (inherits(students, "error")) {
      issues <- c(issues, glue::glue("\u274c Cannot read {student_list_path}: {students$message}"))
    } else {
      required_cols <- c("student_id", "github_username", "ucl_email", "name")
      missing_cols <- setdiff(required_cols, names(students))

      if (length(missing_cols) > 0) {
        issues <- c(
          issues,
          glue::glue("\u274c Missing columns in {student_list_path}: {paste(missing_cols, collapse = ', ')}")
        )
      } else {
        cat(glue::glue("\u2705 Student list file valid ({nrow(students)} students)"), "\n")
      }
    }
  } else {
    issues <- c(issues, glue::glue("\u274c {student_list_path} not found"))
  }

  # Check submissions directory
  if (dir.exists(submissions_path)) {
    n_folders <- length(list.dirs(submissions_path, recursive = FALSE))
    if (n_folders > 0) {
      cat(glue::glue("\u2705 Submissions directory exists ({n_folders} student folders)"), "\n")
    } else {
      issues <- c(issues, glue::glue("\u26a0\ufe0f  Submissions directory '{submissions_path}' is empty"))
    }
  } else {
    issues <- c(issues, glue::glue("\u274c Submissions directory '{submissions_path}' not found"))
  }

  if (length(issues) > 0) {
    cat("\nIssues found:\n")
    for (issue in issues) {
      cat(issue, "\n")
    }
    cat("\nPlease resolve these issues before running the automation.\n")
    return(FALSE)
  } else {
    cat("\n\U0001f389 Configuration is valid! You're ready to run `run_automation()`.\n")
    return(TRUE)
  }
}

#' Create gitignore file
#'
#' Creates a `.gitignore` file configured to ignore R session files,
#' `.Renviron`, `student_list.csv`, `submissions/`, and the `output/` folder.
#'
#' @param output_dir Path to the output directory to ignore. Defaults to `"output"`.
#' @param overwrite Logical; whether to overwrite an existing `.gitignore`. Defaults to `FALSE`.
#'
#' @return Invisibly returns `".gitignore"`.
#' @export
create_gitignore <- function(output_dir = "output", overwrite = FALSE) {
  clean_output <- sub("/+$", "", output_dir)

  gitignore_content <- glue::glue('# R files
.Rhistory
.RData
.Rapp.history
.Rproj.user

# Environment files (contains sensitive tokens)
.Renviron
.env

# Student data and generated output (privacy)
student_list.csv
submissions/
{clean_output}/

# Temporary files
*.tmp
*.log
')

  if (!file.exists(".gitignore") || overwrite) {
    readr::write_file(gitignore_content, ".gitignore")
    cat("Created .gitignore file\n")
  } else {
    cat(".gitignore already exists\n")
  }

  invisible(".gitignore")
}

#' Main set-up function
#'
#' Guides the user through setting up the environment, GitHub authentication,
#' directories (`submissions/` and `output/`), sample student list, `.gitignore`,
#' and starter scripts.
#'
#' @param output_dir Path to the output directory. Defaults to `"output"`.
#'
#' @return Invisibly returns the result of `validate_configuration()`.
#' @export
run_setup <- function(output_dir = "output") {
  cat("GitHub Peer Review System Setup\n")
  cat("===============================\n\n")

  cat("1. Checking required packages...\n")
  install_required_packages()
  cat("\n")

  cat("2. Setting up GitHub authentication...\n")
  setup_github_token()
  cat("\n")

  cat("3. Creating directory structure...\n")
  create_directory_structure(output_dir = output_dir)
  cat("\n")

  cat("4. Creating sample configuration files and starter scripts...\n")
  create_sample_student_list()
  create_gitignore(output_dir = output_dir)
  create_starter_scripts()
  cat("\n")

  cat("5. Validating configuration...\n")
  is_valid <- validate_configuration()
  cat("\n")

  if (is_valid) {
    cat("Setup complete! Next steps:\n")
    cat("1. Edit student_list.csv with your actual student data\n")
    cat("2. Place student submission files in submissions/[student_id]/ folders\n")
    cat("3. Edit and run main_automation_script.R (or call `run_automation()`)\n")
  } else {
    cat("Setup incomplete. Please resolve the issues above.\n")
  }

  invisible(is_valid)
}

#' Configuration helper
#'
#' Prints an example configuration and call to `run_automation()`.
#'
#' @return Invisibly returns the template string.
#' @export
show_configuration_template <- function() {
  cat("Configuration Template\n")
  cat("======================\n")
  cat("Use the following in your script:\n\n")

  template <- 'library(codeinput)

ORG_NAME <- "UCL-StatSci-STAT0001-2025"      # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"            # Current assignment identifier
SUBMISSIONS_PATH <- "submissions"            # Path to student submission folders
OUTPUT_DIR <- "output"                       # Path for generated output files

# Customize these as needed:
REVIEWS_PER_STUDENT <- 2                     # How many reviews each student gives/receives
DEADLINE_DATE <- "2025-04-15"                # Review deadline
INSTRUCTOR_NAME <- "Course Instructor"       # Instructor name for emails

run_automation(
  org_name = ORG_NAME,
  assignment_name = ASSIGNMENT_NAME,
  submissions_path = SUBMISSIONS_PATH,
  output_dir = OUTPUT_DIR,
  reviews_per_student = REVIEWS_PER_STUDENT,
  deadline = DEADLINE_DATE,
  instructor_name = INSTRUCTOR_NAME
)
'

  cat(template)
  invisible(template)
}

#' Test GitHub connection
#'
#' Verifies GitHub authentication via `gh` and optionally checks access to a
#' specified GitHub organization.
#'
#' @param org_name Optional GitHub organization name to test access against.
#'
#' @return Logical `TRUE` if connection succeeds, `FALSE` otherwise.
#' @export
test_github_connection <- function(org_name = NULL) {
  tryCatch({
    user_info <- gh::gh("GET /user")
    cat(glue::glue("\u2705 Successfully connected to GitHub as: {user_info$login}"), "\n")
    cat(glue::glue("Profile: {user_info$html_url}"), "\n")

    if (is.null(org_name) && interactive()) {
      org_name <- trimws(readline("Enter your organization name to test access (or press Enter to skip): "))
    }

    if (!is.null(org_name) && nzchar(org_name)) {
      org_info <- gh::gh("GET /orgs/{org}", org = org_name)
      cat(glue::glue("\u2705 Organization access confirmed: {org_info$login}"), "\n")
    }

    invisible(TRUE)
  }, error = function(e) {
    cat("\u274c GitHub connection failed:\n")
    cat(e$message, "\n")
    cat("Please check your GitHub token setup with `setup_github_token()`.\n")
    invisible(FALSE)
  })
}
