# File Management, Reviewer Assignment, and Main Automation Functions

#' Upload student files from local folder to GitHub repository
#'
#' Uploads all files inside `{base_path}/{student_id}/` into the `submission/`
#' directory of `{org_name}/{repo_name}`.
#'
#' @param repo_name Target GitHub repository name.
#' @param student_id Student identifier corresponding to the subfolder name.
#' @param org_name GitHub organization name.
#' @param base_path Path to the root submissions directory.
#'
#' @return Logical `TRUE` if all files uploaded successfully, `FALSE` otherwise.
#' @export
upload_student_files <- function(repo_name, student_id, org_name, base_path) {
  clean_base <- sub("[/\\\\]+$", "", base_path)
  student_folder <- file.path(clean_base, as.character(student_id))

  if (!dir.exists(student_folder)) {
    warning(glue::glue("Student folder not found: {student_folder}"))
    return(FALSE)
  }

  rel_files <- list.files(student_folder, recursive = TRUE, full.names = FALSE)

  if (length(rel_files) == 0) {
    warning(glue::glue("No files found for student {student_id}"))
    return(FALSE)
  }

  success_count <- 0L

  for (rel_path in rel_files) {
    local_path <- file.path(student_folder, rel_path)
    normalized_rel <- gsub("\\\\", "/", rel_path)
    github_path <- paste0("submission/", normalized_rel)

    success <- upload_single_file(local_path, github_path, repo_name, org_name)
    if (success) success_count <- success_count + 1L
  }

  cat(glue::glue("Uploaded {success_count}/{length(rel_files)} files for {student_id}"), "\n")
  return(success_count == length(rel_files))
}

#' Upload a single file to a GitHub repository
#'
#' @param local_path Path to the local file.
#' @param github_path Destination path inside the GitHub repository.
#' @param repo_name Repository name.
#' @param org_name GitHub organization name.
#'
#' @return Logical `TRUE` on success, `FALSE` on failure.
#' @export
upload_single_file <- function(local_path, github_path, repo_name, org_name) {
  tryCatch({
    if (is_text_file(local_path)) {
      content <- readLines(local_path, warn = FALSE, encoding = "UTF-8")
      content <- paste(content, collapse = "\n")
      content_encoded <- base64enc::base64encode(charToRaw(content))
    } else {
      file_size <- file.info(local_path)$size
      content_raw <- readBin(local_path, "raw", file_size)
      content_encoded <- base64enc::base64encode(content_raw)
    }
    if (length(content_encoded) == 0) {
      content_encoded <- ""
    }

    put_repo_file(
      org_name = org_name,
      repo_name = repo_name,
      github_path = gsub("\\\\", "/", github_path),
      content_encoded = content_encoded,
      message = as.character(glue::glue("Upload {basename(local_path)}"))
    )

    return(TRUE)
  }, error = function(e) {
    warning(glue::glue("Failed to upload {local_path} to {github_path}: {e$message}"))
    return(FALSE)
  })
}

#' Check if file is text-based (for proper encoding)
#'
#' @param file_path Path to a file.
#'
#' @return Logical `TRUE` if the file extension is recognized as text.
#' @export
is_text_file <- function(file_path) {
  ext <- tolower(tools::file_ext(file_path))
  text_extensions <- c(
    "r", "rmd", "qmd", "py", "txt", "md", "csv", "tsv", "json",
    "xml", "html", "css", "js", "sql", "yml", "yaml", "sh", "tex", "bib"
  )
  return(ext %in% text_extensions)
}

#' Assign peer reviewers in a balanced random design
#'
#' Randomly assigns peer reviewers so that every student both receives
#' `reviews_per_student` distinct reviews and performs `reviews_per_student`
#' distinct reviews, with no self-reviews or duplicate pairs.
#'
#' @param students Data frame or tibble containing `student_id`,
#'   `github_username`, `ucl_email`, and `name`.
#' @param reviews_per_student Integer number of reviews each student receives
#'   and performs. Defaults to `2`.
#' @param seed Optional integer random seed for reproducible assignments.
#'
#' @return A tibble of reviewer assignments with columns `reviewed_student_id`,
#'   `reviewed_student_name`, `reviewed_github_username`, `reviewer_student_id`,
#'   `reviewer_name`, `reviewer_github_username`, `reviewer_number`, and
#'   `assigned_branch`.
#' @export
assign_peer_reviewers <- function(students, reviews_per_student = 2, seed = NULL) {
  students <- dplyr::mutate(
    students,
    student_id = as.character(.data$student_id),
    github_username = as.character(.data$github_username),
    name = as.character(.data$name)
  )

  n_students <- nrow(students)
  reviews_per_student <- as.integer(reviews_per_student)

  if (is.na(reviews_per_student) || reviews_per_student < 1L) {
    stop("`reviews_per_student` must be at least 1", call. = FALSE)
  }

  if (n_students < 2L) {
    stop("Need at least 2 students for peer review", call. = FALSE)
  }

  if (n_students <= reviews_per_student) {
    stop(
      glue::glue(
        "Need at least {reviews_per_student + 1} students to assign {reviews_per_student} distinct reviewer(s) per student"
      ),
      call. = FALSE
    )
  }

  if (!is.null(seed)) {
    set.seed(seed)
  }

  # Random permutation of students; each student is reviewed by the next
  # `reviews_per_student` students around the circle.
  perm <- sample.int(n_students)
  permuted_students <- students[perm, , drop = FALSE]

  assignment_rows <- vector("list", n_students * reviews_per_student)
  row_idx <- 1L

  for (i in seq_len(n_students)) {
    reviewed <- permuted_students[i, ]

    for (j in seq_len(reviews_per_student)) {
      reviewer_pos <- ((i + j - 1L) %% n_students) + 1L
      reviewer <- permuted_students[reviewer_pos, ]

      assignment_rows[[row_idx]] <- dplyr::tibble(
        reviewed_student_id = reviewed$student_id,
        reviewed_student_name = reviewed$name,
        reviewed_github_username = reviewed$github_username,
        reviewer_student_id = reviewer$student_id,
        reviewer_name = reviewer$name,
        reviewer_github_username = reviewer$github_username,
        reviewer_number = j,
        assigned_branch = as.character(glue::glue("reviewer-{j}"))
      )
      row_idx <- row_idx + 1L
    }
  }

  assignments <- dplyr::bind_rows(assignment_rows)

  # Order rows matching the input student order, then by reviewer_number
  student_order <- match(assignments$reviewed_student_id, students$student_id)
  assignments <- assignments[order(student_order, assignments$reviewer_number), , drop = FALSE]

  return(assignments)
}

#' Generate distribution information for teachers and students
#'
#' Combines repository URLs and reviewer assignments into summary tables for
#' students, reviewers, and instructors.
#'
#' @param repo_results Tibble containing at least `student_id`, `name`,
#'   `github_username`, and `repo_name` (and optionally `ucl_email`).
#' @param reviewer_assignments Tibble returned by [assign_peer_reviewers()].
#' @param org_name GitHub organization name.
#'
#' @return A list with `student_links`, `reviewer_assignments`, and `teacher_summary`.
#' @export
generate_distribution_info <- function(repo_results, reviewer_assignments, org_name) {
  repo_results <- dplyr::mutate(repo_results, student_id = as.character(.data$student_id))
  reviewer_assignments <- dplyr::mutate(
    reviewer_assignments,
    reviewed_student_id = as.character(.data$reviewed_student_id),
    reviewer_student_id = as.character(.data$reviewer_student_id)
  )

  # Student repository links
  student_links <- repo_results %>%
    dplyr::mutate(
      repo_info = purrr::map(.data$repo_name, ~ get_repo_info(.x, org_name))
    ) %>%
    tidyr::unnest_wider("repo_info") %>%
    dplyr::select(
      dplyr::any_of(c(
        "student_id", "name", "ucl_email", "github_username",
        "repo_name", "html_url", "issues_url", "pulls_url"
      ))
    )

  # Reviewer assignments with URLs
  reviewer_assignments_with_urls <- reviewer_assignments %>%
    dplyr::left_join(
      dplyr::select(student_links, "student_id", reviewed_repo_url = "html_url"),
      by = c("reviewed_student_id" = "student_id")
    ) %>%
    dplyr::mutate(
      review_url = as.character(glue::glue("{reviewed_repo_url}/tree/{assigned_branch}")),
      issues_url = as.character(glue::glue("{reviewed_repo_url}/issues"))
    )

  # Teacher summary
  teacher_summary <- student_links %>%
    dplyr::left_join(
      reviewer_assignments %>%
        dplyr::group_by(.data$reviewed_student_id) %>%
        dplyr::summarise(
          reviewers = paste(.data$reviewer_name, collapse = ", "),
          reviewer_usernames = paste(.data$reviewer_github_username, collapse = ", "),
          .groups = "drop"
        ),
      by = c("student_id" = "reviewed_student_id")
    ) %>%
    dplyr::left_join(
      reviewer_assignments %>%
        dplyr::group_by(.data$reviewer_student_id) %>%
        dplyr::summarise(
          reviewing = paste(.data$reviewed_student_name, collapse = ", "),
          reviewing_repos = paste(
            glue::glue("{reviewed_github_username} ({reviewed_student_id})"),
            collapse = ", "
          ),
          .groups = "drop"
        ),
      by = c("student_id" = "reviewer_student_id")
    )

  return(list(
    student_links = student_links,
    reviewer_assignments = reviewer_assignments_with_urls,
    teacher_summary = teacher_summary
  ))
}

#' Generate email templates for students
#'
#' Writes personalized email text files for each student and a consolidated
#' `email_merge_data.csv` for mail merge.
#'
#' @param distribution_info List returned by [generate_distribution_info()].
#' @param output_dir Directory where email files will be saved. Defaults to
#'   `file.path("output", "email_templates")`.
#' @param deadline Peer review deadline string to insert into emails.
#'   Defaults to `"[DEADLINE]"`.
#' @param instructor_name Instructor name to sign the emails.
#'   Defaults to `"[Your Name]"`.
#'
#' @return Invisibly returns the `email_data` tibble written to `email_merge_data.csv`.
#' @export
generate_email_templates <- function(distribution_info,
                                     output_dir = file.path("output", "email_templates"),
                                     deadline = "[DEADLINE]",
                                     instructor_name = "[Your Name]") {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  student_template <- 'Subject: Your Code Repository and Peer Review Assignment

Dear {name},

Your code submission repository has been set up for peer review. Here are your details:

**Your Repository:**
- URL: {html_url}
- View feedback: {issues_url}
- View suggested changes: {pulls_url}

**What happens next:**
1. Classmates assigned to review your code will provide feedback through Issues
2. They may also suggest code improvements through Pull Requests
3. You will receive email notifications when feedback is posted
4. You can respond to feedback and ask questions in the Issues

**Your reviewing assignments:**
You have been assigned to review code for the following classmates:
{review_assignments}

**Important reminders:**
- Be constructive and helpful in your reviews
- Use the issue template provided
- Complete your reviews by {deadline}
- Contact your instructor if you have technical difficulties

Best regards,
{instructor_name}
'

  for (i in seq_len(nrow(distribution_info$student_links))) {
    student <- distribution_info$student_links[i, ]

    student_reviews <- distribution_info$reviewer_assignments %>%
      dplyr::filter(as.character(.data$reviewer_student_id) == as.character(student$student_id))

    review_text <- ""
    if (nrow(student_reviews) > 0) {
      review_list <- purrr::map_chr(seq_len(nrow(student_reviews)), function(j) {
        review <- student_reviews[j, ]
        as.character(glue::glue("- {review$reviewed_student_name}: {review$review_url}"))
      })
      review_text <- paste(review_list, collapse = "\n")
    }

    email_content <- glue::glue(
      student_template,
      name = student$name,
      html_url = student$html_url,
      issues_url = student$issues_url,
      pulls_url = student$pulls_url,
      review_assignments = ifelse(review_text == "", "None assigned", review_text),
      deadline = deadline,
      instructor_name = instructor_name
    )

    readr::write_file(
      email_content,
      file.path(output_dir, glue::glue("email_{student$student_id}.txt"))
    )
  }

  # Bulk email list for mail merge (retains ucl_email if present in student_links)
  email_data <- distribution_info$student_links %>%
    dplyr::left_join(
      distribution_info$reviewer_assignments %>%
        dplyr::group_by(.data$reviewer_student_id) %>%
        dplyr::summarise(
          review_assignments = paste(
            glue::glue("{reviewed_student_name}: {review_url}"),
            collapse = "\n"
          ),
          .groups = "drop"
        ),
      by = c("student_id" = "reviewer_student_id")
    ) %>%
    dplyr::mutate(
      review_assignments = ifelse(
        is.na(.data$review_assignments),
        "None assigned",
        .data$review_assignments
      ),
      deadline = deadline,
      instructor_name = instructor_name
    )

  readr::write_csv(email_data, file.path(output_dir, "email_merge_data.csv"))

  cat(glue::glue("Email templates generated in {output_dir}"), "\n")
  invisible(email_data)
}

#' Run the full peer review setup and automation workflow
#'
#' Orchestrates repository creation, template and README upload, student code
#' upload, reviewer branch creation, balanced peer reviewer assignment,
#' collaborator permissions (for both authors and reviewers), summary CSV
#' generation, and email template creation.
#'
#' @param org_name GitHub organization name.
#' @param assignment_name Identifier for the assignment. Defaults to `"assignment-1"`.
#' @param student_list_path Path to the student list CSV file. Defaults to `"student_list.csv"`.
#' @param submissions_path Path to the folder containing student submission folders. Defaults to `"submissions"`.
#' @param output_dir Directory to store all generated CSVs and email templates. Defaults to `"output"`.
#' @param reviews_per_student Number of peer reviews each student gives and receives. Defaults to `2`.
#' @param deadline Peer review deadline string for email templates. Defaults to `"[DEADLINE]"`.
#' @param instructor_name Instructor name for email templates. Defaults to `"[Your Name]"`.
#' @param seed Optional random seed for reproducible reviewer assignment.
#'
#' @return A list containing `repo_results`, `reviewer_assignments`,
#'   `permission_results`, and `distribution_info`.
#' @export
run_automation <- function(org_name = NULL,
                           assignment_name = "assignment-1",
                           student_list_path = "student_list.csv",
                           submissions_path = "submissions",
                           output_dir = "output",
                           reviews_per_student = 2,
                           deadline = "[DEADLINE]",
                           instructor_name = "[Your Name]",
                           seed = NULL) {
  check_github_auth()
  org_name <- verify_github_owner(org_name)

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  cat("Reading student data...\n")
  students <- readr::read_csv(
    student_list_path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  students <- validate_student_data(students)

  cat("Assigning peer reviewers...\n")
  reviewer_assignments <- assign_peer_reviewers(
    students,
    reviews_per_student = reviews_per_student,
    seed = seed
  )

  cat("Creating repositories...\n")
  repo_results <- students %>%
    dplyr::mutate(
      repo_name = as.character(glue::glue("student-{student_id}-{assignment_name}")),
      repo_created = purrr::map2_lgl(
        .data$repo_name,
        .data$github_username,
        ~ create_student_repo(.x, .y, org_name)
      )
    )

  cat("Setting up repository structure (templates & README)...\n")
  repo_results <- repo_results %>%
    dplyr::mutate(
      structure_setup = purrr::map_lgl(
        .data$repo_name,
        ~ setup_repo_structure(.x, org_name, create_branches = FALSE)
      )
    )

  cat("Uploading student submissions...\n")
  repo_results <- repo_results %>%
    dplyr::mutate(
      files_uploaded = purrr::map2_lgl(
        .data$repo_name,
        .data$student_id,
        ~ upload_student_files(.x, .y, org_name, submissions_path)
      )
    )

  cat("Creating reviewer branches from uploaded submissions...\n")
  repo_results <- repo_results %>%
    dplyr::mutate(
      branches_created = purrr::map_lgl(
        .data$repo_name,
        ~ create_reviewer_branches(.x, org_name, reviews_per_student = reviews_per_student)
      )
    )

  cat("Setting repository permissions for authors and reviewers...\n")
  permission_results <- purrr::pmap_dfr(
    list(
      repo_results$repo_name,
      repo_results$student_id,
      repo_results$github_username
    ),
    function(r_name, s_id, gh_user) {
      set_reviewer_permissions(
        repo_name = r_name,
        student_id = s_id,
        reviewer_assignments = reviewer_assignments,
        org_name = org_name,
        author_username = gh_user
      )
    }
  )

  cat("Generating distribution information...\n")
  distribution_info <- generate_distribution_info(
    repo_results,
    reviewer_assignments,
    org_name
  )

  cat(glue::glue("Saving results to {output_dir}/..."), "\n")
  readr::write_csv(
    distribution_info$student_links,
    file.path(output_dir, "student_repo_links.csv")
  )
  readr::write_csv(
    distribution_info$reviewer_assignments,
    file.path(output_dir, "reviewer_assignments.csv")
  )
  readr::write_csv(
    distribution_info$teacher_summary,
    file.path(output_dir, "teacher_summary.csv")
  )

  cat("Generating email templates...\n")
  generate_email_templates(
    distribution_info = distribution_info,
    output_dir = file.path(output_dir, "email_templates"),
    deadline = deadline,
    instructor_name = instructor_name
  )

  cat("\n=== SETUP COMPLETE ===\n")
  cat(glue::glue("Repositories created: {sum(repo_results$repo_created)}/{nrow(repo_results)}"), "\n")
  cat(glue::glue("Files uploaded: {sum(repo_results$files_uploaded)}/{nrow(repo_results)}"), "\n")
  cat(glue::glue("Total reviewer assignments: {nrow(reviewer_assignments)}"), "\n")
  cat(glue::glue("\nCheck the '{output_dir}/' folder for distribution files:"), "\n")
  cat(glue::glue("- {file.path(output_dir, 'student_repo_links.csv')}: URLs for each student"), "\n")
  cat(glue::glue("- {file.path(output_dir, 'reviewer_assignments.csv')}: Who reviews whom"), "\n")
  cat(glue::glue("- {file.path(output_dir, 'teacher_summary.csv')}: Complete instructor overview"), "\n")
  cat(glue::glue("- {file.path(output_dir, 'email_templates')}/: Email templates and mail merge CSV"), "\n")

  invisible(list(
    repo_results = repo_results,
    reviewer_assignments = distribution_info$reviewer_assignments,
    permission_results = permission_results,
    distribution_info = distribution_info
  ))
}
