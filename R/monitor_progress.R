# Progress Monitoring, Reporting, Visualization, and Reminder Functions

#' Check if a GitHub issue object represents a Pull Request
#'
#' Note that GitHub's `GET /repos/{owner}/{repo}/issues` endpoint returns both
#' Issues and Pull Requests; Pull Requests contain a non-null `pull_request` field.
#'
#' @param issue A single issue object returned by `gh`.
#'
#' @return Logical `TRUE` if the item is a pull request, `FALSE` otherwise.
#' @keywords internal
is_pull_request <- function(issue) {
  !is.null(issue$pull_request)
}

#' Check if a GitHub issue has the `peer-review` label
#'
#' @param issue A single issue object returned by `gh`.
#'
#' @return Logical `TRUE` if the issue has a `"peer-review"` label.
#' @keywords internal
has_peer_review_label <- function(issue) {
  labels <- issue$labels
  if (is.null(labels) || length(labels) == 0) {
    return(FALSE)
  }

  label_names <- purrr::map_chr(labels, function(lbl) {
    if (is.character(lbl)) {
      lbl[1]
    } else if (is.list(lbl) && !is.null(lbl$name)) {
      as.character(lbl$name)
    } else {
      ""
    }
  })

  "peer-review" %in% tolower(label_names)
}

#' Identify which expected reviewers have submitted a review
#'
#' Matches each reviewer in `expected_reviewers` against the authors of
#' peer-review labeled issues, falling back to any issue or pull request opened
#' by that reviewer in the repository.
#'
#' @param issues List of issue objects from [get_repo_issues()].
#' @param expected_reviewers Character vector of expected reviewer GitHub usernames.
#' @param pulls Optional list of pull request objects from [get_repo_pulls()].
#'
#' @return Character vector of usernames from `expected_reviewers` who have
#'   submitted a review.
#' @keywords internal
get_completed_reviewer_logins <- function(issues, expected_reviewers, pulls = list()) {
  if (length(expected_reviewers) == 0) {
    return(character())
  }

  pure_issues <- purrr::discard(issues, is_pull_request)
  pr_from_issues <- purrr::keep(issues, is_pull_request)
  all_pulls <- c(pulls, pr_from_issues)

  # Authors of issues with the 'peer-review' label
  labeled_issues <- purrr::keep(pure_issues, has_peer_review_label)
  labeled_authors <- tolower(purrr::map_chr(labeled_issues, ~ as.character(.x$user$login %||% "")))

  # Fallback: authors of any issue or pull request in the repository
  any_issue_authors <- tolower(purrr::map_chr(pure_issues, ~ as.character(.x$user$login %||% "")))
  any_pull_authors <- tolower(purrr::map_chr(all_pulls, ~ as.character(.x$user$login %||% "")))
  all_authors <- unique(c(labeled_authors, any_issue_authors, any_pull_authors))

  completed_mask <- tolower(expected_reviewers) %in% all_authors
  expected_reviewers[completed_mask]
}

#' Resolve `student_id` for a `repo_name`
#'
#' Matches `repo_name` against known `reviewed_student_id` values in
#' `reviewer_assignments` (avoiding greedy regex failures when `assignment_name`
#' contains hyphens such as `"assignment-1"`).
#'
#' @param repo_name Repository name (e.g., `"student-12345-assignment-1"`).
#' @param reviewer_assignments Tibble of reviewer assignments.
#' @param assignment_name Optional assignment identifier.
#'
#' @return Character `student_id`.
#' @keywords internal
resolve_student_id_from_repo <- function(repo_name, reviewer_assignments, assignment_name = NULL) {
  # 1. If assignment_name is provided, strip exact prefix and suffix
  if (!is.null(assignment_name) && nzchar(assignment_name)) {
    prefix <- "student-"
    suffix <- paste0("-", assignment_name)
    if (startsWith(repo_name, prefix) && endsWith(repo_name, suffix)) {
      extracted <- substr(
        repo_name,
        nchar(prefix) + 1L,
        nchar(repo_name) - nchar(suffix)
      )
      if (nzchar(extracted)) return(extracted)
    }
  }

  # 2. Match against known reviewed_student_id values in reviewer_assignments
  if (!is.null(reviewer_assignments) && "reviewed_student_id" %in% names(reviewer_assignments)) {
    known_ids <- unique(as.character(reviewer_assignments$reviewed_student_id))
    # Sort longest first so prefix matching is unambiguous
    known_ids <- known_ids[order(nchar(known_ids), decreasing = TRUE)]
    for (id in known_ids) {
      if (startsWith(repo_name, paste0("student-", id, "-")) || identical(repo_name, id)) {
        return(id)
      }
    }
  }

  # 3. Non-greedy fallback up to first hyphen after student-
  sub("^student-([^-]+)-.*$", "\\1", repo_name)
}

#' Monitor review completion across student repositories
#'
#' Queries GitHub Issues and Pull Requests for each student repository and
#' determines review completion rates and per-reviewer submission status.
#'
#' @param org_name GitHub organization name.
#' @param repo_names Character vector of student repository names.
#' @param reviewer_assignments Tibble of reviewer assignments.
#' @param assignment_name Optional assignment name to assist with student ID resolution.
#'
#' @return A tibble with repository-level progress metrics and a
#'   `completed_reviewer_usernames` column (comma-separated logins).
#' @export
monitor_review_progress <- function(org_name,
                                    repo_names,
                                    reviewer_assignments,
                                    assignment_name = NULL) {
  cat("Checking review progress...\n")

  reviewer_assignments <- dplyr::mutate(
    reviewer_assignments,
    reviewed_student_id = as.character(.data$reviewed_student_id),
    reviewer_student_id = as.character(.data$reviewer_student_id)
  )

  progress_data <- purrr::map_dfr(repo_names, function(repo_name) {
    cat(glue::glue("Checking {repo_name}..."), "\n")

    student_id <- resolve_student_id_from_repo(
      repo_name = repo_name,
      reviewer_assignments = reviewer_assignments,
      assignment_name = assignment_name
    )

    raw_issues <- get_repo_issues(org_name, repo_name)
    pure_issues <- purrr::discard(raw_issues, is_pull_request)
    pulls <- get_repo_pulls(org_name, repo_name)

    expected_reviewers <- reviewer_assignments %>%
      dplyr::filter(.data$reviewed_student_id == student_id) %>%
      dplyr::pull(.data$reviewer_github_username)

    completed_logins <- get_completed_reviewer_logins(
      issues = pure_issues,
      expected_reviewers = expected_reviewers,
      pulls = pulls
    )
    completed_reviews <- length(completed_logins)
    n_expected <- length(expected_reviewers)

    dplyr::tibble(
      repo_name = repo_name,
      student_id = as.character(student_id),
      total_issues = length(pure_issues),
      peer_review_issues = sum(purrr::map_lgl(pure_issues, has_peer_review_label)),
      total_pulls = length(pulls),
      expected_reviewers = n_expected,
      completed_reviews = completed_reviews,
      completion_rate = if (n_expected > 0) completed_reviews / n_expected else NA_real_,
      completed_reviewer_usernames = paste(completed_logins, collapse = ", "),
      last_activity = get_last_activity_date(pure_issues, pulls)
    )
  })

  return(progress_data)
}

#' Get issues for a repository
#'
#' @param org_name GitHub organization name.
#' @param repo_name Repository name.
#'
#' @return A list of issue objects from GitHub.
#' @export
get_repo_issues <- function(org_name, repo_name) {
  tryCatch({
    issues <- gh::gh(
      "GET /repos/{owner}/{repo}/issues",
      owner = org_name,
      repo = repo_name,
      state = "all",
      per_page = 100
    )
    return(issues)
  }, error = function(e) {
    warning(glue::glue("Failed to get issues for {repo_name}: {e$message}"))
    return(list())
  })
}

#' Get pull requests for a repository
#'
#' @param org_name GitHub organization name.
#' @param repo_name Repository name.
#'
#' @return A list of pull request objects from GitHub.
#' @export
get_repo_pulls <- function(org_name, repo_name) {
  tryCatch({
    pulls <- gh::gh(
      "GET /repos/{owner}/{repo}/pulls",
      owner = org_name,
      repo = repo_name,
      state = "all",
      per_page = 100
    )
    return(pulls)
  }, error = function(e) {
    warning(glue::glue("Failed to get pulls for {repo_name}: {e$message}"))
    return(list())
  })
}

#' Check how many expected reviewers have completed their reviews
#'
#' @param issues List of GitHub issue objects.
#' @param expected_reviewers Character vector of expected reviewer GitHub usernames.
#' @param pulls Optional list of GitHub pull request objects.
#'
#' @return Integer count of expected reviewers who submitted a review.
#' @export
check_completed_reviews <- function(issues, expected_reviewers, pulls = list()) {
  if (length(issues) == 0 && length(pulls) == 0) {
    return(0L)
  }

  completed_logins <- get_completed_reviewer_logins(
    issues = issues,
    expected_reviewers = expected_reviewers,
    pulls = pulls
  )

  return(length(completed_logins))
}

#' Get last activity date from issues and pull requests
#'
#' @param issues List of GitHub issue objects.
#' @param pulls List of GitHub pull request objects.
#'
#' @return Character string of the latest `updated_at` timestamp, or `NA_character_`.
#' @export
get_last_activity_date <- function(issues, pulls) {
  all_items <- c(issues, pulls)

  if (length(all_items) == 0) {
    return(NA_character_)
  }

  dates <- purrr::map_chr(all_items, ~ as.character(.x$updated_at %||% NA_character_))
  dates <- dates[!is.na(dates) & nzchar(dates)]

  if (length(dates) == 0) {
    return(NA_character_)
  }

  latest_date <- max(lubridate::as_datetime(dates), na.rm = TRUE)
  return(as.character(latest_date))
}

#' Annotate each reviewer assignment row with whether the review is complete
#'
#' @param progress_data Tibble returned by [monitor_review_progress()].
#' @param reviewer_assignments Tibble of reviewer assignments.
#'
#' @return `reviewer_assignments` with an added logical column `review_completed`.
#' @keywords internal
annotate_assignment_completion <- function(progress_data, reviewer_assignments) {
  progress_lookup <- progress_data %>%
    dplyr::mutate(student_id = as.character(.data$student_id)) %>%
    dplyr::select(
      "student_id",
      "repo_name",
      "completion_rate",
      dplyr::any_of("completed_reviewer_usernames")
    )

  annotated <- reviewer_assignments %>%
    dplyr::mutate(
      reviewed_student_id = as.character(.data$reviewed_student_id),
      reviewer_student_id = as.character(.data$reviewer_student_id)
    ) %>%
    dplyr::left_join(
      progress_lookup,
      by = c("reviewed_student_id" = "student_id")
    )

  has_completed_col <- "completed_reviewer_usernames" %in% names(annotated)

  annotated$review_completed <- purrr::map_lgl(seq_len(nrow(annotated)), function(i) {
    row <- annotated[i, ]
    if (has_completed_col && !is.na(row$completed_reviewer_usernames)) {
      completed_vec <- trimws(unlist(strsplit(as.character(row$completed_reviewer_usernames), ",")))
      completed_vec <- completed_vec[nzchar(completed_vec)]
      tolower(row$reviewer_github_username) %in% tolower(completed_vec)
    } else {
      !is.na(row$completion_rate) && row$completion_rate >= 1
    }
  })

  annotated
}

#' Generate progress report
#'
#' Computes overall summary metrics, student-level (reviewee) completion, and
#' reviewer-level completion.
#'
#' @param progress_data Tibble returned by [monitor_review_progress()].
#' @param students Data frame or tibble of students.
#' @param reviewer_assignments Tibble of reviewer assignments.
#'
#' @return A list with `summary`, `student_progress`, and `reviewer_progress`.
#' @export
generate_progress_report <- function(progress_data, students, reviewer_assignments) {
  students <- dplyr::mutate(students, student_id = as.character(.data$student_id))
  progress_data <- dplyr::mutate(progress_data, student_id = as.character(.data$student_id))

  total_students <- nrow(students)
  total_expected_reviews <- nrow(reviewer_assignments)
  total_completed_reviews <- sum(progress_data$completed_reviews, na.rm = TRUE)

  # Student-level completion (reviews received on their repository)
  student_progress <- progress_data %>%
    dplyr::left_join(students, by = "student_id") %>%
    dplyr::arrange(dplyr::desc(.data$completion_rate), dplyr::desc(.data$total_issues))

  # Reviewer-level completion (reviews performed by each reviewer)
  annotated_assignments <- annotate_assignment_completion(progress_data, reviewer_assignments)

  reviewer_progress <- annotated_assignments %>%
    dplyr::group_by(
      .data$reviewer_student_id,
      .data$reviewer_name,
      .data$reviewer_github_username
    ) %>%
    dplyr::summarise(
      assigned_reviews = dplyr::n(),
      completed_reviews = sum(.data$review_completed, na.rm = TRUE),
      pending_reviews = sum(!.data$review_completed, na.rm = TRUE),
      completion_rate = .data$completed_reviews / .data$assigned_reviews,
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(.data$completion_rate), .data$reviewer_student_id)

  summary_stats <- list(
    total_students = total_students,
    students_with_complete_reviews = sum(progress_data$completion_rate == 1, na.rm = TRUE),
    students_with_partial_reviews = sum(
      progress_data$completion_rate > 0 & progress_data$completion_rate < 1,
      na.rm = TRUE
    ),
    students_with_no_reviews = sum(progress_data$completion_rate == 0, na.rm = TRUE),
    total_expected_reviews = total_expected_reviews,
    total_completed_reviews = total_completed_reviews,
    overall_completion_rate = if (total_expected_reviews > 0) {
      total_completed_reviews / total_expected_reviews
    } else {
      NA_real_
    },
    repositories_with_pulls = sum(progress_data$total_pulls > 0, na.rm = TRUE),
    avg_issues_per_repo = mean(progress_data$total_issues, na.rm = TRUE),
    avg_pulls_per_repo = mean(progress_data$total_pulls, na.rm = TRUE)
  )

  return(list(
    summary = summary_stats,
    student_progress = student_progress,
    reviewer_progress = reviewer_progress
  ))
}

#' Create progress visualizations
#'
#' Generates and saves completion rate distribution and issues-vs-pulls plots.
#'
#' @param progress_data Tibble returned by [monitor_review_progress()].
#' @param output_dir Directory to save PNG plots. Defaults to
#'   `file.path("output", "progress_reports")`.
#'
#' @return Invisibly returns a list of `ggplot` objects.
#' @export
create_progress_visualizations <- function(progress_data,
                                           output_dir = file.path("output", "progress_reports")) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  p1 <- ggplot2::ggplot(progress_data, ggplot2::aes(x = .data$completion_rate)) +
    ggplot2::geom_histogram(bins = 5, fill = "skyblue", color = "black", alpha = 0.7) +
    ggplot2::scale_x_continuous(labels = scales::percent) +
    ggplot2::labs(
      title = "Distribution of Review Completion Rates",
      x = "Completion Rate",
      y = "Number of Students"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    file.path(output_dir, "completion_distribution.png"),
    p1,
    width = 8,
    height = 6
  )

  p2 <- ggplot2::ggplot(
    progress_data,
    ggplot2::aes(x = .data$total_issues, y = .data$total_pulls)
  ) +
    ggplot2::geom_point(ggplot2::aes(color = .data$completion_rate), size = 3, alpha = 0.7) +
    ggplot2::scale_color_gradient(low = "red", high = "green", labels = scales::percent) +
    ggplot2::labs(
      title = "Issues vs Pull Requests by Repository",
      x = "Total Issues",
      y = "Total Pull Requests",
      color = "Completion Rate"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    file.path(output_dir, "issues_vs_pulls.png"),
    p2,
    width = 8,
    height = 6
  )

  cat(glue::glue("Visualizations saved to {output_dir}"), "\n")
  invisible(list(completion_distribution = p1, issues_vs_pulls = p2))
}

#' Generate reminder emails for incomplete reviews
#'
#' Identifies specific reviewer-assignment pairs that have not yet been
#' completed and writes personalized reminder email templates only for
#' reviewers who still have pending reviews.
#'
#' @param progress_data Tibble returned by [monitor_review_progress()].
#' @param reviewer_assignments Tibble of reviewer assignments.
#' @param output_dir Directory where reminder email `.txt` files will be saved.
#'   Defaults to `file.path("output", "reminders")`.
#' @param deadline Peer review deadline string. Defaults to `"[DEADLINE]"`.
#' @param instructor_name Instructor name for email sign-off. Defaults to `"[Your Name]"`.
#'
#' @return Invisibly returns the tibble of `incomplete_reviewers`.
#' @export
generate_reminder_emails <- function(progress_data,
                                     reviewer_assignments,
                                     output_dir = file.path("output", "reminders"),
                                     deadline = "[DEADLINE]",
                                     instructor_name = "[Your Name]") {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  annotated <- annotate_assignment_completion(progress_data, reviewer_assignments)

  if (!"review_url" %in% names(annotated)) {
    annotated <- dplyr::mutate(
      annotated,
      review_url = ifelse(
        !is.na(.data$repo_name),
        as.character(glue::glue("{repo_name} (branch: {assigned_branch})")),
        as.character(.data$assigned_branch)
      )
    )
  }

  incomplete_reviewers <- annotated %>%
    dplyr::filter(!.data$review_completed) %>%
    dplyr::group_by(.data$reviewer_student_id, .data$reviewer_name) %>%
    dplyr::summarise(
      pending_reviews = list(as.character(glue::glue("- {reviewed_student_name}: {review_url}"))),
      .groups = "drop"
    )

  reminder_template <- 'Subject: Reminder: Pending Code Reviews

Dear {reviewer_name},

This is a friendly reminder that you have pending code reviews to complete.

**Your pending reviews:**
{pending_review_list}

**To complete your review:**
1. Visit the repository URL
2. Review the code in the submission folder
3. Create a new Issue using the peer review template
4. Provide constructive feedback

**Deadline:** {deadline}

If you\'re having technical difficulties, please contact your instructor.

Best regards,
{instructor_name}
'

  for (i in seq_len(nrow(incomplete_reviewers))) {
    reviewer <- incomplete_reviewers[i, ]
    review_list <- paste(unlist(reviewer$pending_reviews), collapse = "\n")

    email_content <- glue::glue(
      reminder_template,
      reviewer_name = reviewer$reviewer_name,
      pending_review_list = review_list,
      deadline = deadline,
      instructor_name = instructor_name
    )

    readr::write_file(
      email_content,
      file.path(output_dir, glue::glue("reminder_{reviewer$reviewer_student_id}.txt"))
    )
  }

  cat(glue::glue("Reminder emails generated for {nrow(incomplete_reviewers)} students"), "\n")
  invisible(incomplete_reviewers)
}

#' Main progress monitoring function
#'
#' Checks review completion across all student repositories, prints summary
#' statistics, saves progress CSVs in `output_dir`, creates visualizations in
#' `{output_dir}/progress_reports`, and generates targeted reminder emails in
#' `{output_dir}/reminders`.
#'
#' @param org_name GitHub organization name.
#' @param assignment_name Assignment identifier. Defaults to `"assignment-1"`.
#' @param student_list_path Path to `student_list.csv`. Defaults to `"student_list.csv"`.
#' @param output_dir Output directory containing `reviewer_assignments.csv` and
#'   where reports/reminders will be saved. Defaults to `"output"`.
#' @param deadline Peer review deadline string for reminder emails. Defaults to `"[DEADLINE]"`.
#' @param instructor_name Instructor name for reminder emails. Defaults to `"[Your Name]"`.
#'
#' @return The progress report list returned by [generate_progress_report()].
#' @export
run_progress_check <- function(org_name,
                               assignment_name = "assignment-1",
                               student_list_path = "student_list.csv",
                               output_dir = "output",
                               deadline = "[DEADLINE]",
                               instructor_name = "[Your Name]") {
  cat("=== PEER REVIEW PROGRESS CHECK ===\n")
  cat(glue::glue("Time: {Sys.time()}"), "\n\n")

  check_github_auth()

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  students <- readr::read_csv(
    student_list_path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )

  assignments_path <- file.path(output_dir, "reviewer_assignments.csv")
  if (!file.exists(assignments_path) && file.exists("reviewer_assignments.csv")) {
    assignments_path <- "reviewer_assignments.csv"
  }
  if (!file.exists(assignments_path)) {
    stop(
      glue::glue("Could not find reviewer_assignments.csv in '{output_dir}/' or working directory."),
      call. = FALSE
    )
  }

  reviewer_assignments <- readr::read_csv(
    assignments_path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )

  repo_names <- students %>%
    dplyr::mutate(repo_name = as.character(glue::glue("student-{student_id}-{assignment_name}"))) %>%
    dplyr::pull(.data$repo_name)

  progress_data <- monitor_review_progress(
    org_name = org_name,
    repo_names = repo_names,
    reviewer_assignments = reviewer_assignments,
    assignment_name = assignment_name
  )

  report <- generate_progress_report(progress_data, students, reviewer_assignments)

  cat("SUMMARY STATISTICS:\n")
  cat(glue::glue("Total students: {report$summary$total_students}"), "\n")
  cat(glue::glue("Students with complete reviews: {report$summary$students_with_complete_reviews}"), "\n")
  cat(glue::glue("Students with partial reviews: {report$summary$students_with_partial_reviews}"), "\n")
  cat(glue::glue("Students with no reviews: {report$summary$students_with_no_reviews}"), "\n")
  cat(glue::glue("Overall completion rate: {scales::percent(report$summary$overall_completion_rate)}"), "\n")
  cat(glue::glue("Repositories with pull requests: {report$summary$repositories_with_pulls}"), "\n\n")

  date_str <- as.character(Sys.Date())
  readr::write_csv(
    progress_data,
    file.path(output_dir, glue::glue("progress_check_{date_str}.csv"))
  )
  readr::write_csv(
    report$student_progress,
    file.path(output_dir, glue::glue("student_progress_{date_str}.csv"))
  )
  readr::write_csv(
    report$reviewer_progress,
    file.path(output_dir, glue::glue("reviewer_progress_{date_str}.csv"))
  )

  create_progress_visualizations(
    progress_data,
    output_dir = file.path(output_dir, "progress_reports")
  )

  if (!is.na(report$summary$overall_completion_rate) && report$summary$overall_completion_rate < 1) {
    generate_reminder_emails(
      progress_data = progress_data,
      reviewer_assignments = reviewer_assignments,
      output_dir = file.path(output_dir, "reminders"),
      deadline = deadline,
      instructor_name = instructor_name
    )
    cat("Reminder emails generated for incomplete reviews\n")
  }

  cat("\nProgress check complete!\n")
  return(report)
}
