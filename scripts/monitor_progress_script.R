# Progress Monitoring Script
# Track completion of peer reviews and generate reports

library(codeinput)

# Configuration
ORG_NAME <- "UCL-StatSci-STAT0001-2025"      # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"            # Current assignment identifier
STUDENT_LIST_PATH <- "student_list.csv"      # Path to student list CSV
OUTPUT_DIR <- "output"                       # Directory containing reviewer_assignments.csv
DEADLINE_DATE <- "2025-04-15"                # Review deadline for reminder emails
INSTRUCTOR_NAME <- "Course Instructor"       # Name for reminder email sign-off

# Run the progress check
if (interactive()) {
  report <- run_progress_check(
    org_name = ORG_NAME,
    assignment_name = ASSIGNMENT_NAME,
    student_list_path = STUDENT_LIST_PATH,
    output_dir = OUTPUT_DIR,
    deadline = DEADLINE_DATE,
    instructor_name = INSTRUCTOR_NAME
  )
}
