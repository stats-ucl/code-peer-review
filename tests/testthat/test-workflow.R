test_that("validate_student_data validates columns, types, and duplicates", {
  students <- dplyr::tibble(
    student_id = c(12345, 12346, 12347),
    github_username = c("alice_gh", "bob_gh", "carol_gh"),
    ucl_email = c("alice@ucl.ac.uk", "bob@ucl.ac.uk", "carol@ucl.ac.uk"),
    name = c("Alice", "Bob", "Carol")
  )

  validated <- validate_student_data(students)
  expect_type(validated$student_id, "character")
  expect_equal(validated$student_id, c("12345", "12346", "12347"))

  # Missing column
  bad_students <- dplyr::select(students, -"ucl_email")
  expect_error(validate_student_data(bad_students), "Missing required columns")

  # Duplicate student_id
  dup_students <- dplyr::bind_rows(students, students[1, ])
  expect_error(validate_student_data(dup_students), "Duplicate student_id")

  # Missing github_username triggers warning
  missing_gh <- students
  missing_gh$github_username[2] <- ""
  expect_warning(validate_student_data(missing_gh), "missing GitHub usernames")
})

test_that("assign_peer_reviewers produces balanced, self-free, duplicate-free assignments", {
  students <- dplyr::tibble(
    student_id = as.character(101:107),
    github_username = paste0("user_", 101:107),
    ucl_email = paste0("user", 101:107, "@ucl.ac.uk"),
    name = paste("Student", 101:107)
  )

  assignments <- assign_peer_reviewers(students, reviews_per_student = 2, seed = 42)
  expect_equal(nrow(assignments), nrow(students) * 2)

  # No self-reviews
  expect_true(all(assignments$reviewed_student_id != assignments$reviewer_student_id))

  # No duplicate reviewer-reviewee pairs
  pair_keys <- paste(assignments$reviewed_student_id, assignments$reviewer_student_id, sep = "->")
  expect_equal(length(unique(pair_keys)), nrow(assignments))

  # Every student receives exactly 2 reviews
  received_counts <- table(assignments$reviewed_student_id)
  expect_equal(as.integer(received_counts), rep(2L, nrow(students)))

  # Every student performs exactly 2 reviews (balanced workload)
  given_counts <- table(assignments$reviewer_student_id)
  expect_equal(as.integer(given_counts), rep(2L, nrow(students)))

  # Reproducibility with seed
  assignments_repeat <- assign_peer_reviewers(students, reviews_per_student = 2, seed = 42)
  expect_equal(assignments, assignments_repeat)

  # 2 students with reviews_per_student = 1 swaps them
  swap_assignments <- assign_peer_reviewers(students[1:2, ], reviews_per_student = 1)
  expect_equal(nrow(swap_assignments), 2L)
  expect_equal(swap_assignments$reviewed_student_id, c("101", "102"))
  expect_equal(swap_assignments$reviewer_student_id, c("102", "101"))

  # Edge cases
  expect_error(assign_peer_reviewers(students[1, ], reviews_per_student = 1), "Need at least 2 students")
  expect_error(assign_peer_reviewers(students[1:2, ], reviews_per_student = 2), "Need at least 3 students")
  expect_error(assign_peer_reviewers(students[1:3, ], reviews_per_student = 3), "Need at least 4 students")
})

test_that("is_text_file identifies code and text extensions including Rmd and qmd", {
  expect_true(is_text_file("analysis.R"))
  expect_true(is_text_file("report.Rmd"))
  expect_true(is_text_file("notebook.qmd"))
  expect_true(is_text_file("data.csv"))
  expect_false(is_text_file("plot.png"))
  expect_false(is_text_file("model.rds"))
})

test_that("resolve_student_id_from_repo handles hyphenated assignment names", {
  assignments <- dplyr::tibble(
    reviewed_student_id = c("12345", "67890"),
    reviewer_student_id = c("67890", "12345")
  )

  expect_equal(
    resolve_student_id_from_repo("student-12345-assignment-1", assignments, "assignment-1"),
    "12345"
  )
  expect_equal(
    resolve_student_id_from_repo("student-12345-assignment-1", assignments),
    "12345"
  )
})

test_that("check_completed_reviews handles gh label objects, fallback issues/PRs, and filters PRs", {
  expected <- c("alice_gh", "bob_gh")

  # Mock GitHub issue with nested label object as returned by `gh`
  issues <- list(
    list(
      user = list(login = "alice_gh"),
      labels = list(list(name = "peer-review")),
      updated_at = "2026-03-01T10:00:00Z"
    ),
    # A PR returned by the /issues endpoint (has pull_request field) from an unrelated user
    list(
      user = list(login = "other_user"),
      labels = list(),
      pull_request = list(url = "https://api.github.com/..."),
      updated_at = "2026-03-02T10:00:00Z"
    )
  )

  expect_equal(check_completed_reviews(issues, expected), 1L)

  # Fallback: bob_gh submits an unlabeled issue or PR
  pulls <- list(
    list(
      user = list(login = "bob_gh"),
      updated_at = "2026-03-03T10:00:00Z"
    )
  )
  expect_equal(check_completed_reviews(issues, expected, pulls = pulls), 2L)
})

test_that("generate_progress_report and generate_reminder_emails track individual reviewers accurately", {
  students <- dplyr::tibble(
    student_id = c("1", "2", "3"),
    github_username = c("u1", "u2", "u3"),
    ucl_email = c("u1@ucl.ac.uk", "u2@ucl.ac.uk", "u3@ucl.ac.uk"),
    name = c("Student One", "Student Two", "Student Three")
  )

  assignments <- dplyr::tibble(
    reviewed_student_id = c("1", "1", "2", "2", "3", "3"),
    reviewed_student_name = c("Student One", "Student One", "Student Two", "Student Two", "Student Three", "Student Three"),
    reviewed_github_username = c("u1", "u1", "u2", "u2", "u3", "u3"),
    reviewer_student_id = c("2", "3", "3", "1", "1", "2"),
    reviewer_name = c("Student Two", "Student Three", "Student Three", "Student One", "Student One", "Student Two"),
    reviewer_github_username = c("u2", "u3", "u3", "u1", "u1", "u2"),
    reviewer_number = c(1L, 2L, 1L, 2L, 1L, 2L),
    assigned_branch = c("reviewer-1", "reviewer-2", "reviewer-1", "reviewer-2", "reviewer-1", "reviewer-2"),
    review_url = paste0("https://github.com/org/repo-", c("1", "1", "2", "2", "3", "3"))
  )

  # Suppose u1 completed both of their assigned reviews (for student 2 and student 3),
  # u2 completed 1 review (for student 1) but not for student 3,
  # and u3 completed 0 reviews.
  progress_data <- dplyr::tibble(
    repo_name = c("student-1-a1", "student-2-a1", "student-3-a1"),
    student_id = c("1", "2", "3"),
    total_issues = c(1L, 1L, 1L),
    peer_review_issues = c(1L, 1L, 1L),
    total_pulls = c(0L, 0L, 0L),
    expected_reviewers = c(2L, 2L, 2L),
    completed_reviews = c(1L, 1L, 1L),
    completion_rate = c(0.5, 0.5, 0.5),
    completed_reviewer_usernames = c("u2", "u1", "u1"),
    last_activity = c("2026-03-01", "2026-03-01", "2026-03-01")
  )

  report <- generate_progress_report(progress_data, students, assignments)

  # Check reviewer_progress: u1 completed 2/2, u2 completed 1/2, u3 completed 0/2
  rp <- report$reviewer_progress
  expect_equal(rp$completed_reviews[rp$reviewer_student_id == "1"], 2L)
  expect_equal(rp$pending_reviews[rp$reviewer_student_id == "1"], 0L)
  expect_equal(rp$completed_reviews[rp$reviewer_student_id == "2"], 1L)
  expect_equal(rp$pending_reviews[rp$reviewer_student_id == "2"], 1L)
  expect_equal(rp$completed_reviews[rp$reviewer_student_id == "3"], 0L)
  expect_equal(rp$pending_reviews[rp$reviewer_student_id == "3"], 2L)

  # Check reminder emails: u1 should NOT receive a reminder email!
  tmp_reminders <- file.path(tempdir(), "test_reminders")
  unlink(tmp_reminders, recursive = TRUE)

  incomplete <- generate_reminder_emails(
    progress_data = progress_data,
    reviewer_assignments = assignments,
    output_dir = tmp_reminders,
    deadline = "2026-05-01",
    instructor_name = "Dr. Smith"
  )

  expect_equal(sort(incomplete$reviewer_student_id), c("2", "3"))
  expect_false(file.exists(file.path(tmp_reminders, "reminder_1.txt")))
  expect_true(file.exists(file.path(tmp_reminders, "reminder_2.txt")))
  expect_true(file.exists(file.path(tmp_reminders, "reminder_3.txt")))

  reminder_2_text <- readr::read_file(file.path(tmp_reminders, "reminder_2.txt"))
  expect_match(reminder_2_text, "Student Three")
  expect_no_match(reminder_2_text, "Student One")
  expect_match(reminder_2_text, "2026-05-01")
  expect_match(reminder_2_text, "Dr. Smith")

  unlink(tmp_reminders, recursive = TRUE)
})

test_that("generate_email_templates populates deadline, instructor, and ucl_email", {
  dist_info <- list(
    student_links = dplyr::tibble(
      student_id = c("1", "2"),
      name = c("Alice", "Bob"),
      ucl_email = c("alice@ucl.ac.uk", "bob@ucl.ac.uk"),
      github_username = c("alice_gh", "bob_gh"),
      repo_name = c("student-1-a1", "student-2-a1"),
      html_url = c("https://github.com/org/s1", "https://github.com/org/s2"),
      issues_url = c("https://github.com/org/s1/issues", "https://github.com/org/s2/issues"),
      pulls_url = c("https://github.com/org/s1/pulls", "https://github.com/org/s2/pulls")
    ),
    reviewer_assignments = dplyr::tibble(
      reviewed_student_id = c("1", "2"),
      reviewed_student_name = c("Alice", "Bob"),
      reviewed_github_username = c("alice_gh", "bob_gh"),
      reviewer_student_id = c("2", "1"),
      reviewer_name = c("Bob", "Alice"),
      reviewer_github_username = c("bob_gh", "alice_gh"),
      reviewer_number = c(1L, 1L),
      assigned_branch = c("reviewer-1", "reviewer-1"),
      review_url = c("https://github.com/org/s1/tree/reviewer-1", "https://github.com/org/s2/tree/reviewer-1")
    )
  )

  tmp_emails <- file.path(tempdir(), "test_emails")
  unlink(tmp_emails, recursive = TRUE)

  email_df <- generate_email_templates(
    distribution_info = dist_info,
    output_dir = tmp_emails,
    deadline = "2026-04-30",
    instructor_name = "Prof. Green"
  )

  expect_true("ucl_email" %in% names(email_df))
  expect_equal(email_df$ucl_email, c("alice@ucl.ac.uk", "bob@ucl.ac.uk"))

  email_1 <- readr::read_file(file.path(tmp_emails, "email_1.txt"))
  expect_match(email_1, "2026-04-30")
  expect_match(email_1, "Prof. Green")
  expect_match(email_1, "Bob: https://github.com/org/s2/tree/reviewer-1")

  unlink(tmp_emails, recursive = TRUE)
})
