# Set-up and Configuration Script
# Prepares the environment and data files for the GitHub peer review system

# Load required libraries
library(dplyr)
library(readr)
library(glue)

# Run setup if script is executed directly

if (interactive()) {
  cat("GitHub Peer Review Setup Script\n")
  cat("Choose an option:\n")
  cat("1. Run full setup\n")
  cat("2. Test GitHub connection\n")
  cat("3. Show configuration template\n")
  cat("4. Validate current configuration\n")
  
  choice <- readline("Enter choice (1-4): ")
  
  switch(choice,
    "1" = run_setup(),
    "2" = test_github_connection(),
    "3" = show_configuration_template(),
    "4" = validate_configuration(),
    cat("Invalid choice\n")
  )
}

# run_setup()
# test_github_connection()
# show_configuration_template()
# validate_configuration()
