# Monitor review completion
monitor_review_progress <- function(org_name, repo_names, reviewer_assignments) {
  cat("Checking review progress...\n")
  
  progress_data <- map_dfr(repo_names, function(repo_name) {
    cat(glue("Checking {repo_name}...\n"))
    
    # Extract student ID from repo name
    student_id <- gsub("student-(.+)-.*", "\\1", repo_name)
    
    # Get issues for this repository
    issues <- get_repo_issues(org_name, repo_name)
    
    # Get pull requests
    pulls <- get_repo_pulls(org_name, repo_name)
    
    # Get expected reviewers for this student
    expected_reviewers <- reviewer_assignments %>%
      filter(reviewed_student_id == student_id) %>%
      pull(reviewer_github_username)
    
    # Check which reviewers have submitted reviews
    completed_reviews <- check_completed_reviews(issues, expected_reviewers)
    
    tibble(
      repo_name = repo_name,
      student_id = student_id,
      total_issues = length(issues),
      peer_review_issues = sum(map_lgl(issues, ~"peer-review" %in% .x$labels)),
      total_pulls = length(pulls),
      expected_reviewers = length(expected_reviewers),
      completed_reviews = completed_reviews,
      completion_rate = completed_reviews / length(expected_reviewers),
      last_activity = get_last_activity_date(issues, pulls)
    )
  })
  
  return(progress_data)
}

# Get issues for a repository
get_repo_issues <- function(org_name, repo_name) {
  tryCatch({
    issues <- gh("GET /repos/{owner}/{repo}/issues",
                 owner = org_name, repo = repo_name,
                 state = "all", per_page = 100)
    return(issues)
  }, error = function(e) {
    warning(glue("Failed to get issues for {repo_name}: {e$message}"))
    return(list())
  })
}

# Get pull requests for a repository  
get_repo_pulls <- function(org_name, repo_name) {
  tryCatch({
    pulls <- gh("GET /repos/{owner}/{repo}/pulls",
                owner = org_name, repo = repo_name,
                state = "all", per_page = 100)
    return(pulls)
  }, error = function(e) {
    warning(glue("Failed to get pulls for {repo_name}: {e$message}"))
    return(list())
  })
}

# Check which reviewers have completed their reviews
check_completed_reviews <- function(issues, expected_reviewers) {
  if (length(issues) == 0) return(0)
  
  # Look for peer review issues
  peer_review_issues <- keep(issues, ~"peer-review" %in% map_chr(.x$labels, "name"))
  
  if (length(peer_review_issues) == 0) return(0)
  
  # Check which reviewers have submitted
  reviewers_who_submitted <- map_chr(peer_review_issues, ~.x$user$login)
  completed <- sum(expected_reviewers %in% reviewers_who_submitted)
  
  return(completed)
}

# Get last activity date from issues and pulls
get_last_activity_date <- function(issues, pulls) {
  all_items <- c(issues, pulls)
  
  if (length(all_items) == 0) return(NA)
  
  dates <- map_chr(all_items, ~.x$updated_at)
  latest_date <- max(as_datetime(dates), na.rm = TRUE)
  
  return(as.character(latest_date))
}

# Generate progress report
generate_progress_report <- function(progress_data, students, reviewer_assignments) {
  
  # Overall statistics
  total_students <- nrow(students)
  total_expected_reviews <- nrow(reviewer_assignments)
  total_completed_reviews <- sum(progress_data$completed_reviews)
  
  # Student-level completion
  student_progress <- progress_data %>%
    left_join(students, by = "student_id") %>%
    arrange(desc(completion_rate), desc(total_issues))
  
  # Reviewer-level completion (who's doing their reviews)
  reviewer_progress <- reviewer_assignments %>%
    left_join(
      progress_data %>% select(student_id, repo_name),
      by = c("reviewed_student_id" = "student_id")
    ) %>%
    group_by(reviewer_student_id, reviewer_name) %>%
    summarise(
      assigned_reviews = n(),
      # This would need to be checked against actual issue submissions
      .groups = "drop"
    )
  
  # Summary statistics
  summary_stats <- list(
    total_students = total_students,
    students_with_complete_reviews = sum(progress_data$completion_rate == 1),
    students_with_partial_reviews = sum(progress_data$completion_rate > 0 & progress_data$completion_rate < 1),
    students_with_no_reviews = sum(progress_data$completion_rate == 0),
    total_expected_reviews = total_expected_reviews,
    total_completed_reviews = total_completed_reviews,
    overall_completion_rate = total_completed_reviews / total_expected_reviews,
    repositories_with_pulls = sum(progress_data$total_pulls > 0),
    avg_issues_per_repo = mean(progress_data$total_issues),
    avg_pulls_per_repo = mean(progress_data$total_pulls)
  )
  
  return(list(
    summary = summary_stats,
    student_progress = student_progress,
    reviewer_progress = reviewer_progress
  ))
}

# Create visualizations
create_progress_visualizations <- function(progress_data, output_dir = "progress_reports/") {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Completion rate distribution
  p1 <- ggplot(progress_data, aes(x = completion_rate)) +
    geom_histogram(bins = 5, fill = "skyblue", color = "black", alpha = 0.7) +
    scale_x_continuous(labels = scales::percent) +
    labs(
      title = "Distribution of Review Completion Rates",
      x = "Completion Rate",
      y = "Number of Students"
    ) +
    theme_minimal()
  
  ggsave(file.path(output_dir, "completion_distribution.png"), p1, width = 8, height = 6)
  
  # Issues vs Pulls scatter
  p2 <- ggplot(progress_data, aes(x = total_issues, y = total_pulls)) +
    geom_point(aes(color = completion_rate), size = 3, alpha = 0.7) +
    scale_color_gradient(low = "red", high = "green", labels = scales::percent) +
    labs(
      title = "Issues vs Pull Requests by Repository",
      x = "Total Issues",
      y = "Total Pull Requests",
      color = "Completion Rate"
    ) +
    theme_minimal()
  
  ggsave(file.path(output_dir, "issues_vs_pulls.png"), p2, width = 8, height = 6)
  
  cat(glue("Visualizations saved to {output_dir}\n"))
}

# Generate reminder emails for incomplete reviews
generate_reminder_emails <- function(progress_data, reviewer_assignments, output_dir = "reminders/") {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Find students who haven't completed their reviewing duties
  incomplete_reviewers <- reviewer_assignments %>%
    left_join(
      progress_data %>% select(student_id, completion_rate),
      by = c("reviewed_student_id" = "student_id")
    ) %>%
    filter(completion_rate < 1) %>%
    group_by(reviewer_student_id, reviewer_name) %>%
    summarise(
      pending_reviews = list(glue("{reviewed_student_name}: {review_url}")),
      .groups = "drop"
    )
  
  # Create reminder email template
  reminder_template <- '
Subject: Reminder: Pending Code Reviews

Dear {reviewer_name},

This is a friendly reminder that you have pending code reviews to complete.

**Your pending reviews:**
{pending_review_list}

**To complete your review:**
1. Visit the repository URL
2. Review the code in the submission folder
3. Create a new Issue using the peer review template
4. Provide constructive feedback

**Deadline:** [INSERT DEADLINE]

If you\'re having technical difficulties, please contact your instructor.

Best regards,
[Your Name]
'
  
  # Generate individual reminder emails
  for (i in 1:nrow(incomplete_reviewers)) {
    reviewer <- incomplete_reviewers[i, ]
    
    review_list <- paste(unlist(reviewer$pending_reviews), collapse = "\n")
    
    email_content <- glue(reminder_template,
                          reviewer_name = reviewer$reviewer_name,
                          pending_review_list = review_list)
    
    write_file(email_content, 
               file.path(output_dir, glue("reminder_{reviewer$reviewer_student_id}.txt")))
  }
  
  cat(glue("Reminder emails generated for {nrow(incomplete_reviewers)} students\n"))
}

# Main monitoring function
run_progress_check <- function() {
  cat("=== PEER REVIEW PROGRESS CHECK ===\n")
  cat(glue("Time: {Sys.time()}\n\n"))
  
  # Get progress data
  progress_data <- monitor_review_progress(ORG_NAME, repo_names, reviewer_assignments)
  
  # Generate report
  report <- generate_progress_report(progress_data, students, reviewer_assignments)
  
  # Print summary
  cat("SUMMARY STATISTICS:\n")
  cat(glue("Total students: {report$summary$total_students}\n"))
  cat(glue("Students with complete reviews: {report$summary$students_with_complete_reviews}\n"))
  cat(glue("Students with partial reviews: {report$summary$students_with_partial_reviews}\n"))
  cat(glue("Students with no reviews: {report$summary$students_with_no_reviews}\n"))
  cat(glue("Overall completion rate: {scales::percent(report$summary$overall_completion_rate)}\n"))
  cat(glue("Repositories with pull requests: {report$summary$repositories_with_pulls}\n\n"))
  
  # Save detailed data
  write_csv(progress_data, glue("progress_check_{Sys.Date()}.csv"))
  write_csv(report$student_progress, glue("student_progress_{Sys.Date()}.csv"))
  
  # Create visualizations
  create_progress_visualizations(progress_data)
  
  # Generate reminders if needed
  if (report$summary$overall_completion_rate < 1) {
    generate_reminder_emails(progress_data, reviewer_assignments)
    cat("Reminder emails generated for incomplete reviews\n")
  }
  
  cat("\nProgress check complete!\n")
  
  return(report)
}