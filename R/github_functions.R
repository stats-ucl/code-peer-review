# GitHub API Helper Functions
# Contains all GitHub-specific operations for the peer review system

#' Check GitHub authentication
#'
#' Verifies that a valid GitHub token is configured and can authenticate with
#' the GitHub API.
#'
#' @return Logical `TRUE` if authenticated; throws an error otherwise.
#' @export
check_github_auth <- function() {
  if (file.exists(".Renviron")) {
    readRenviron(".Renviron")
  }
  tryCatch({
    user_info <- gh::gh("GET /user")
    cat(glue::glue("Authenticated as: {user_info$login}"), "\n")
    return(TRUE)
  }, error = function(e) {
    stop(
      "GitHub authentication failed. Run `setup_github_token()` or set GITHUB_TOKEN.",
      call. = FALSE
    )
  })
}

#' Validate student data format
#'
#' Validates that the student data frame contains required columns
#' (`student_id`, `github_username`, `ucl_email`, `name`), coerces `student_id`
#' to character, and warns if any GitHub usernames are missing.
#'
#' @param students Data frame or tibble of student information.
#'
#' @return The validated `students` tibble (with `student_id` as character), invisibly.
#' @export
validate_student_data <- function(students) {
  required_cols <- c("student_id", "github_username", "ucl_email", "name")
  missing_cols <- setdiff(required_cols, names(students))

  if (length(missing_cols) > 0) {
    stop(
      glue::glue("Missing required columns: {paste(missing_cols, collapse = ', ')}"),
      call. = FALSE
    )
  }

  students <- dplyr::mutate(
    students,
    student_id = trimws(as.character(.data$student_id)),
    github_username = trimws(as.character(.data$github_username))
  )

  if (anyDuplicated(students$student_id) > 0) {
    dup_ids <- unique(students$student_id[duplicated(students$student_id)])
    stop(
      glue::glue("Duplicate student_id values found: {paste(dup_ids, collapse = ', ')}"),
      call. = FALSE
    )
  }

  missing_github <- dplyr::filter(
    students,
    is.na(.data$github_username) | .data$github_username == ""
  )
  if (nrow(missing_github) > 0) {
    warning(
      glue::glue("Students missing GitHub usernames: {paste(missing_github$name, collapse = ', ')}"),
      call. = FALSE
    )
  }

  cat(glue::glue("Validated data for {nrow(students)} students"), "\n")
  invisible(students)
}

#' Create or update a file in a GitHub repository (idempotent)
#'
#' Checks whether `github_path` already exists in the repository to obtain its
#' `sha` before calling `PUT /repos/{owner}/{repo}/contents/{path}`.
#'
#' @param org_name GitHub organization or owner name.
#' @param repo_name Repository name.
#' @param github_path Destination path within the repository.
#' @param content_encoded Base64-encoded file content string.
#' @param message Commit message.
#'
#' @return Invisibly returns the GitHub API response.
#' @keywords internal
put_repo_file <- function(org_name, repo_name, github_path, content_encoded, message) {
  existing <- tryCatch(
    gh::gh(
      "GET /repos/{owner}/{repo}/contents/{path}",
      owner = org_name,
      repo = repo_name,
      path = github_path
    ),
    error = function(e) NULL
  )

  if (!is.null(existing) && !is.null(existing$sha)) {
    gh::gh(
      "PUT /repos/{owner}/{repo}/contents/{path}",
      owner = org_name,
      repo = repo_name,
      path = github_path,
      message = message,
      content = content_encoded,
      sha = existing$sha
    )
  } else {
    gh::gh(
      "PUT /repos/{owner}/{repo}/contents/{path}",
      owner = org_name,
      repo = repo_name,
      path = github_path,
      message = message,
      content = content_encoded
    )
  }
}

#' Check that target GitHub organization or user account exists
#'
#' Validates that `org_name` exists on GitHub (either as a GitHub organization
#' or as the authenticated user's personal account). In an interactive session,
#' if `org_name` does not exist on GitHub, offers to use the authenticated
#' user's personal account or open GitHub in the browser to create the
#' organization.
#'
#' @param org_name GitHub organization name (or authenticated user's login).
#'
#' @return Character string of the verified `org_name` (potentially updated to
#'   the user's personal login if chosen interactively).
#' @keywords internal
verify_github_owner <- function(org_name) {
  user_info <- gh::gh("GET /user")
  if (is.null(org_name) || !nzchar(trimws(org_name))) {
    cat(glue::glue("No `org_name` specified; using your personal GitHub account: {user_info$login}"), "\n")
    return(user_info$login)
  }

  if (tolower(org_name) == tolower(user_info$login)) {
    return(user_info$login)
  }

  org_exists <- tryCatch({
    gh::gh("GET /orgs/{org}", org = org_name)
    TRUE
  }, error = function(e) FALSE)

  if (org_exists) {
    return(org_name)
  }

  if (interactive()) {
    cat(glue::glue("\n\u26a0\ufe0f  GitHub organization '{org_name}' was not found on GitHub."), "\n")
    cat("Note: GitHub does not allow creating organizations automatically via the API.\n")
    cat("You can either:\n")
    cat(glue::glue("  1. Create the repositories under your personal GitHub account ('{user_info$login}') right now"), "\n")
    cat(glue::glue("  2. Open https://github.com/account/organizations/new in your browser to create '{org_name}' manually"), "\n")
    cat("  3. Cancel and stop\n\n")

    choice <- trimws(readline("Choose option (1, 2, or 3) [default: 1]: "))
    if (choice == "" || choice == "1") {
      cat(glue::glue("Using personal GitHub account '{user_info$login}' instead of '{org_name}'."), "\n")
      return(user_info$login)
    } else if (choice == "2") {
      utils::browseURL("https://github.com/account/organizations/new")
      readline(glue::glue("Press Enter once you have created the organization '{org_name}' on GitHub..."))
      recheck <- tryCatch({
        gh::gh("GET /orgs/{org}", org = org_name)
        TRUE
      }, error = function(e) FALSE)
      if (recheck) {
        return(org_name)
      }
    }
  }

  stop(
    glue::glue(
      "GitHub organization '{org_name}' was not found (or your token lacks access to it).\n",
      "To fix this, either:\n",
      "  1. Pass your personal GitHub username (`org_name = \"{user_info$login}\"`) to create repositories under your own account, OR\n",
      "  2. Create the organization '{org_name}' on GitHub first at https://github.com/account/organizations/new"
    ),
    call. = FALSE
  )
}

#' Create a repository for a student
#'
#' Creates a private GitHub repository in `org_name` (or under the authenticated
#' user's account if `org_name` matches their login) for a student's submission.
#' If the repository already exists, returns `TRUE` without failing.
#'
#' @param repo_name Name of the repository to create.
#' @param github_username Student's GitHub username.
#' @param org_name GitHub organization name (or authenticated user's username).
#'
#' @return Logical `TRUE` if created (or already exists), `FALSE` on error.
#' @export
create_student_repo <- function(repo_name, github_username, org_name) {
  tryCatch({
    existing <- tryCatch(
      gh::gh("GET /repos/{owner}/{repo}", owner = org_name, repo = repo_name),
      error = function(e) NULL
    )

    if (!is.null(existing)) {
      cat(glue::glue("Repository already exists: {repo_name}"), "\n")
      return(TRUE)
    }

    user_info <- tryCatch(gh::gh("GET /user"), error = function(e) list(login = ""))
    is_personal_account <- tolower(org_name) == tolower(user_info$login %||% "")

    if (is_personal_account) {
      gh::gh(
        "POST /user/repos",
        name = repo_name,
        description = glue::glue("Code submission repository for {github_username}"),
        private = TRUE,
        auto_init = TRUE,
        has_issues = TRUE
      )
    } else {
      gh::gh(
        "POST /orgs/{org}/repos",
        org = org_name,
        name = repo_name,
        description = glue::glue("Code submission repository for {github_username}"),
        private = TRUE,
        auto_init = TRUE,
        has_issues = TRUE
      )
    }

    cat(glue::glue("Created repository: {repo_name}"), "\n")
    return(TRUE)
  }, error = function(e) {
    warning(glue::glue("Failed to create repository {repo_name}: {e$message}"))
    return(FALSE)
  })
}

#' Set up repository structure (templates, README, submission folder, and optional branches)
#'
#' Configures the repository with a `README.md`, `submission/.gitkeep`,
#' `.github/ISSUE_TEMPLATE/peer-review.md`, and the `peer-review` issue label.
#' Note: Reviewer branches (`reviewer-1..N`) should be created *after* student
#' files are uploaded using [create_reviewer_branches()] so that reviewer
#' branches contain the uploaded submission files.
#'
#' @param repo_name Repository name.
#' @param org_name GitHub organization name.
#' @param create_branches Logical; if `TRUE`, also calls [create_reviewer_branches()].
#'   Defaults to `FALSE` so branches can be created after file upload.
#' @param reviews_per_student Number of reviewer branches to create if `create_branches = TRUE`.
#'
#' @return Logical `TRUE` on success, `FALSE` on error.
#' @export
setup_repo_structure <- function(repo_name,
                                 org_name,
                                 create_branches = FALSE,
                                 reviews_per_student = 2) {
  tryCatch({
    # Create .github issue template and peer-review label
    create_github_templates(repo_name, org_name)
    create_peer_review_label(repo_name, org_name)

    # Create initial folder structure and README
    create_folder_structure(repo_name, org_name)

    # Optionally create reviewer branches
    if (create_branches) {
      create_reviewer_branches(
        repo_name = repo_name,
        org_name = org_name,
        reviews_per_student = reviews_per_student
      )
    }

    cat(glue::glue("Set up structure for: {repo_name}"), "\n")
    return(TRUE)
  }, error = function(e) {
    warning(glue::glue("Failed to setup structure for {repo_name}: {e$message}"))
    return(FALSE)
  })
}

#' Create reviewer branches from the default branch
#'
#' Creates (or updates) `reviewer-1` through `reviewer-{reviews_per_student}`
#' branches pointing to the latest commit on `main` (or the repository's default
#' branch). Call this *after* uploading student submission files so reviewer
#' branches include all submission files and templates.
#'
#' @param repo_name Repository name.
#' @param org_name GitHub organization name.
#' @param reviews_per_student Number of reviewer branches to create. Defaults to `2`.
#'
#' @return Logical `TRUE` on success, `FALSE` on error.
#' @export
create_reviewer_branches <- function(repo_name, org_name, reviews_per_student = 2) {
  tryCatch({
    repo_info <- gh::gh("GET /repos/{owner}/{repo}", owner = org_name, repo = repo_name)
    default_branch <- repo_info$default_branch %||% "main"

    branch_ref <- gh::gh(
      "GET /repos/{owner}/{repo}/git/ref/heads/{branch}",
      owner = org_name,
      repo = repo_name,
      branch = default_branch
    )
    main_sha <- branch_ref$object$sha

    for (j in seq_len(reviews_per_student)) {
      branch_name <- glue::glue("reviewer-{j}")
      existing_ref <- tryCatch(
        gh::gh(
          "GET /repos/{owner}/{repo}/git/ref/heads/{branch}",
          owner = org_name,
          repo = repo_name,
          branch = branch_name
        ),
        error = function(e) NULL
      )

      if (is.null(existing_ref)) {
        gh::gh(
          "POST /repos/{owner}/{repo}/git/refs",
          owner = org_name,
          repo = repo_name,
          ref = glue::glue("refs/heads/{branch_name}"),
          sha = main_sha
        )
      } else {
        gh::gh(
          "PATCH /repos/{owner}/{repo}/git/refs/heads/{branch}",
          owner = org_name,
          repo = repo_name,
          branch = branch_name,
          sha = main_sha,
          force = TRUE
        )
      }
    }

    cat(glue::glue("Created {reviews_per_student} reviewer branch(es) for: {repo_name}"), "\n")
    return(TRUE)
  }, error = function(e) {
    warning(glue::glue("Failed to create reviewer branches for {repo_name}: {e$message}"))
    return(FALSE)
  })
}

#' Ensure peer-review label exists in repository
#'
#' @param repo_name Repository name.
#' @param org_name GitHub organization name.
#'
#' @return Invisibly returns `TRUE`.
#' @keywords internal
create_peer_review_label <- function(repo_name, org_name) {
  tryCatch({
    gh::gh(
      "POST /repos/{owner}/{repo}/labels",
      owner = org_name,
      repo = repo_name,
      name = "peer-review",
      color = "0e8a16",
      description = "Peer code review feedback"
    )
  }, error = function(e) {
    # Ignore if label already exists (422)
    NULL
  })
  invisible(TRUE)
}

#' Create GitHub issue templates
#'
#' Uploads `.github/ISSUE_TEMPLATE/peer-review.md` to a student's repository.
#'
#' @param repo_name Repository name.
#' @param org_name GitHub organization name.
#'
#' @return Invisibly returns the GitHub API response.
#' @export
create_github_templates <- function(repo_name, org_name) {
  peer_review_template <- '---
name: Peer Review
about: Template for peer code review
title: "Peer Review by [Your Name]"
labels: "peer-review"
assignees: ""
---

## Code Review Checklist

### Code Quality
- [ ] Code runs without errors
- [ ] Code is well-formatted and readable
- [ ] Variable names are meaningful
- [ ] Comments are helpful and appropriate

### Correctness
- [ ] Code appears to solve the problem correctly
- [ ] Logic flow is clear and sensible
- [ ] Edge cases are handled appropriately

### Feedback

**What worked well:**
[Describe what you liked about this code]

**Suggestions for improvement:**
[Provide constructive suggestions]

**Questions:**
[Ask any questions about the approach or implementation]

**Overall assessment:**
[Rate 1-5 with brief justification]

### What I learned:
[Describe anything new you learned from reviewing this code]

### Technical Notes:
- Review completed on branch: [specify branch]
- Files reviewed: [list main files]
- Time spent on review: [approximate time]
'

  put_repo_file(
    org_name = org_name,
    repo_name = repo_name,
    github_path = ".github/ISSUE_TEMPLATE/peer-review.md",
    content_encoded = base64enc::base64encode(charToRaw(peer_review_template)),
    message = "Add peer review issue template"
  )
}

#' Create initial folder structure
#'
#' Uploads the assignment `README.md` and `submission/.gitkeep` to the
#' student repository.
#'
#' @param repo_name Repository name.
#' @param org_name GitHub organization name.
#'
#' @return Invisibly returns `TRUE`.
#' @export
create_folder_structure <- function(repo_name, org_name) {
  readme_content <- glue::glue('# Code Assignment Repository

This repository contains your code submission and peer review materials.

## Structure
- `submission/` - Your original code files
- `feedback/` - Peer review feedback will appear here
- `solutions/` - Reference solutions (if provided)

## How to Use
1. Your code has been uploaded to the `submission/` folder
2. Two classmates will review your code and create Issues with feedback
3. You can view their feedback in the Issues tab
4. You may receive Pull Requests with suggested improvements

## Getting Help
- Check the student guide provided by your instructor
- Ask questions during lab sessions
- Contact your instructor if you encounter technical issues

Good luck with the peer review process!
')

  put_repo_file(
    org_name = org_name,
    repo_name = repo_name,
    github_path = "README.md",
    content_encoded = base64enc::base64encode(charToRaw(readme_content)),
    message = "Add initial README"
  )

  put_repo_file(
    org_name = org_name,
    repo_name = repo_name,
    github_path = "submission/.gitkeep",
    content_encoded = base64enc::base64encode( raw(0) ),
    message = "Create submission folder"
  )

  invisible(TRUE)
}

#' Set repository permissions for the submitting student and assigned reviewers
#'
#' Grants repository access (default `"push"`, i.e., write permission) to both
#' the submitting student (author) and their assigned peer reviewers.
#'
#' @param repo_name Repository name.
#' @param student_id Student ID of the repository author.
#' @param reviewer_assignments Tibble returned by [assign_peer_reviewers()].
#' @param org_name GitHub organization name.
#' @param author_username Optional GitHub username of the submitting student. If
#'   `NULL`, looked up from `reviewer_assignments`.
#' @param permission Collaborator permission level (`"push"`, `"pull"`, `"triage"`,
#'   `"maintain"`, or `"admin"`). `"write"` is automatically mapped to `"push"`.
#'
#' @return A tibble recording permission grant results for each user.
#' @export
set_reviewer_permissions <- function(repo_name,
                                     student_id,
                                     reviewer_assignments,
                                     org_name,
                                     author_username = NULL,
                                     permission = "push") {
  if (identical(permission, "write")) {
    permission <- "push"
  }

  target_id <- as.character(student_id)
  student_reviewers <- dplyr::filter(
    reviewer_assignments,
    as.character(.data$reviewed_student_id) == target_id
  )

  if (is.null(author_username) && nrow(student_reviewers) > 0) {
    author_username <- student_reviewers$reviewed_github_username[1]
  }

  collaborators <- dplyr::tibble(
    username = character(),
    role = character()
  )

  if (!is.null(author_username) && !is.na(author_username) && nzchar(author_username)) {
    collaborators <- dplyr::bind_rows(
      collaborators,
      dplyr::tibble(username = author_username, role = "author")
    )
  }

  if (nrow(student_reviewers) > 0) {
    collaborators <- dplyr::bind_rows(
      collaborators,
      dplyr::tibble(
        username = student_reviewers$reviewer_github_username,
        role = "reviewer"
      )
    )
  }

  collaborators <- dplyr::distinct(collaborators, .data$username, .keep_all = TRUE)

  if (nrow(collaborators) == 0) {
    return(dplyr::tibble(
      repo_name = character(),
      username = character(),
      role = character(),
      reviewer_username = character(),
      success = logical(),
      error = character()
    ))
  }

  results <- purrr::map_dfr(seq_len(nrow(collaborators)), function(i) {
    user <- collaborators$username[i]
    role <- collaborators$role[i]

    tryCatch({
      gh::gh(
        "PUT /repos/{owner}/{repo}/collaborators/{username}",
        owner = org_name,
        repo = repo_name,
        username = user,
        permission = permission
      )

      cat(glue::glue("Added {user} ({role}) as collaborator to {repo_name}"), "\n")

      dplyr::tibble(
        repo_name = repo_name,
        username = user,
        role = role,
        reviewer_username = user,
        success = TRUE,
        error = NA_character_
      )
    }, error = function(e) {
      warning(glue::glue("Failed to add {user} ({role}) to {repo_name}: {e$message}"))

      dplyr::tibble(
        repo_name = repo_name,
        username = user,
        role = role,
        reviewer_username = user,
        success = FALSE,
        error = e$message
      )
    })
  })

  return(results)
}

#' Get repository URLs and information
#'
#' @param repo_name Repository name.
#' @param org_name GitHub organization name.
#'
#' @return Named list with `html_url`, `clone_url`, `issues_url`, and `pulls_url`.
#' @export
get_repo_info <- function(repo_name, org_name) {
  tryCatch({
    repo <- gh::gh("GET /repos/{owner}/{repo}", owner = org_name, repo = repo_name)

    list(
      html_url = repo$html_url,
      clone_url = repo$clone_url,
      issues_url = as.character(glue::glue("{repo$html_url}/issues")),
      pulls_url = as.character(glue::glue("{repo$html_url}/pulls"))
    )
  }, error = function(e) {
    warning(glue::glue("Failed to get info for {repo_name}: {e$message}"))
    list(
      html_url = NA_character_,
      clone_url = NA_character_,
      issues_url = NA_character_,
      pulls_url = NA_character_
    )
  })
}

#' Check repository access for a user
#'
#' @param repo_name Repository name.
#' @param username GitHub username.
#' @param org_name GitHub organization name.
#'
#' @return Logical `TRUE` if `username` is a collaborator on `repo_name`, `FALSE` otherwise.
#' @export
check_repo_access <- function(repo_name, username, org_name) {
  tryCatch({
    gh::gh(
      "GET /repos/{owner}/{repo}/collaborators/{username}",
      owner = org_name,
      repo = repo_name,
      username = username
    )
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}
