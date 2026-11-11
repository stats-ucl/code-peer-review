# GitHub Code Peer Review Automation Script
# Main orchestration script for setting up repositories and peer review assignments

library(codeinput)

# Configuration
ORG_NAME <- "UCL-StatSci-STAT0001-2025"      # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"            # Current assignment identifier
STUDENT_LIST_PATH <- "student_list.csv"      # Path to student list CSV
LOCAL_SUBMISSIONS_PATH <- "submissions"      # Path to local student submission folders
OUTPUT_DIR <- "output"                       # Directory for generated output files
REVIEWS_PER_STUDENT <- 2                     # Number of peer reviews per student
DEADLINE_DATE <- "2025-04-15"                # Review deadline
INSTRUCTOR_NAME <- "Course Instructor"       # Name for email sign-off

if (interactive()) {
  results <- run_automation(
    org_name = ORG_NAME,
    assignment_name = ASSIGNMENT_NAME,
    student_list_path = STUDENT_LIST_PATH,
    submissions_path = LOCAL_SUBMISSIONS_PATH,
    output_dir = OUTPUT_DIR,
    reviews_per_student = REVIEWS_PER_STUDENT,
    deadline = DEADLINE_DATE,
    instructor_name = INSTRUCTOR_NAME
  )
}
