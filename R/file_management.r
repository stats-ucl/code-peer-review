# File Management Functions
# Handles uploading student files from local folders to GitHub repositories

# Upload student files from local folder to GitHub repository
upload_student_files <- function(repo_name, student_id, org_name, base_path) {
  student_folder <- file.path(base_path, student_id)
  
  # Check if student folder exists
  if (!dir.exists(student_folder)) {
    warning(glue("Student folder not found: {student_folder}"))
    return(FALSE)
  }
  
  # Get list of files in student folder
  files <- list.files(student_folder, recursive = TRUE, full.names = TRUE)
  
  if (length(files) == 0) {
    warning(glue("No files found for student {student_id}"))
    return(FALSE)
  }
  
  success_count <- 0
  
  for (file_path in files) {
    # Get relative path from student folder
    rel_path <- gsub(paste0(student_folder, "/"), "", file_path)
    github_path <- file.path("submission", rel_path)
    
    success <- upload_single_file(file_path, github_path, repo_name, org_name)
    if (success) success_count <- success_count + 1
  }
  
  cat(glue("Uploaded {success_count}/{length(files)} files for {student_id}\n"))
  return(success_count == length(files))
}

# Upload a single file to GitHub repository
upload_single_file <- function(local_path, github_path, repo_name, org_name) {
  tryCatch({
    # Read file content
    if (is_text_file(local_path)) {
      content <- readLines(local_path, warn = FALSE)
      content <- paste(content, collapse = "\n")
      content_encoded <- base64encode(charToRaw(content))
    } else {
      # For binary files
      content_raw <- readBin(local_path, "raw", file.info(local_path)$size)
      content_encoded <- base64encode(content_raw)
    }
    
    # Upload to GitHub
    gh("PUT /repos/{owner}/{repo}/contents/{path}",
       owner = org_name, repo = repo_name, path = github_path,
       message = glue("Upload {basename(local_path)}"),
       content = content_encoded)
    
    return(TRUE)
  }, error = function(e) {
    warning(glue("Failed to upload {local_path} to {github_path}: {e$message}"))
    return(FALSE)
  })
}

# Check if file is text-based (for proper encoding)
is_text_file <- function(file_path) {
  ext <- tolower(tools::file_ext(file_path))
  text_extensions <- c("r", "py", "txt", "md", "csv", "json", "xml", "html", "css", "js", "sql", "yml", "yaml")
  return(ext %in% text_extensions)
}

# Assign peer reviewers randomly
assign_peer_reviewers <- function(students, reviews_per_student = 2) {
  n_students <- nrow(students)
  
  if (n_students < 3) {
    stop("Need at least 3 students for peer review")
  }
  
  # Create assignment matrix
  assignments <- tibble()
  
  for (i in 1:n_students) {
    student <- students[i, ]
    
    # Get potential reviewers (exclude self)
    potential_reviewers <- students[-i, ]
    
    # Randomly sample reviewers
    if (nrow(potential_reviewers) >= reviews_per_student) {
      selected_reviewers <- sample_n(potential_reviewers, reviews_per_student)
    } else {
      selected_reviewers <- potential_reviewers
    }
    
    # Create assignment records
    for (j in 1:nrow(selected_reviewers)) {
      assignments <- bind_rows(assignments, tibble(
        reviewed_student_id = student$student_id,
        reviewed_student_name = student$name,
        reviewed_github_username = student$github_username,
        reviewer_student_id = selected_reviewers$student_id[j],
        reviewer_name = selected_reviewers$name[j],
        reviewer_github_username = selected_reviewers$github_username[j],
        reviewer_number = j,
        assigned_branch = glue("reviewer-{j}")
      ))
    }
  }
  
  return(assignments)
}

# Generate distribution information for teachers and students
generate_distribution_info <- function(repo_results, reviewer_assignments, org_name) {
  
  # Student repository links
  student_links <- repo_results %>%
    mutate(
      repo_info = map(repo_name, ~get_repo_info(.x, org_name))
    ) %>%
    unnest_wider(repo_info) %>%
    select(student_id, name, github_username, repo_name, html_url, issues_url, pulls_url)
  
  # Reviewer assignments with URLs
  reviewer_assignments_with_urls <- reviewer_assignments %>%
    left_join(
      student_links %>% select(student_id, reviewed_repo_url = html_url),
      by = c("reviewed_student_id" = "student_id")
    ) %>%
    mutate(
      review_url = glue("{reviewed_repo_url}/tree/{assigned_branch}"),
      issues_url = glue("{reviewed_repo_url}/issues")
    )
  
  # Teacher summary
  teacher_summary <- student_links %>%
    left_join(
      reviewer_assignments %>% 
        group_by(reviewed_student_id) %>%
        summarise(
          reviewers = paste(reviewer_name, collapse = ", "),
          reviewer_usernames = paste(reviewer_github_username, collapse = ", "),
          .groups = "drop"
        ),
      by = c("student_id" = "reviewed_student_id")
    ) %>%
    left_join(
      reviewer_assignments %>%
        group_by(reviewer_student_id) %>%
        summarise(
          reviewing = paste(reviewed_student_name, collapse = ", "),
          reviewing_repos = paste(glue("{reviewed_github_username} ({reviewed_student_id})"), collapse = ", "),
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

# Generate email templates
generate_email_templates <- function(distribution_info, output_dir) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Student notification template
  student_template <- '
Subject: Your Code Repository and Peer Review Assignment

Dear {name},

Your code submission repository has been set up for peer review. Here are your details:

**Your Repository:**
- URL: {html_url}
- View feedback: {issues_url}
- View suggested changes: {pulls_url}

**What happens next:**
1. Two classmates will review your code and provide feedback through Issues
2. They may also suggest code improvements through Pull Requests
3. You will receive email notifications when feedback is posted
4. You can respond to feedback and ask questions in the Issues

**Your reviewing assignments:**
You have been assigned to review code for the following classmates:
{review_assignments}

**Important reminders:**
- Be constructive and helpful in your reviews
- Use the issue template provided
- Complete your reviews by [DEADLINE]
- Contact your instructor if you have technical difficulties

Best regards,
[Your Name]
'

  # Write individual student emails
  for (i in 1:nrow(distribution_info$student_links)) {
    student <- distribution_info$student_links[i, ]
    
    # Get review assignments for this student
    student_reviews <- distribution_info$reviewer_assignments %>%
      filter(reviewer_student_id == student$student_id)
    
    review_text <- ""
    if (nrow(student_reviews) > 0) {
      review_list <- map_chr(1:nrow(student_reviews), function(j) {
        review <- student_reviews[j, ]
        glue("- {review$reviewed_student_name}: {review$review_url}")
      })
      review_text <- paste(review_list, collapse = "\n")
    }
    
    email_content <- glue(student_template,
                         name = student$name,
                         html_url = student$html_url,
                         issues_url = student$issues_url,
                         pulls_url = student$pulls_url,
                         review_assignments = ifelse(review_text == "", "None assigned", review_text))
    
    write_file(email_content, file.path(output_dir, glue("email_{student$student_id}.txt")))
  }
  
  # Bulk email list for mail merge
  email_data <- distribution_info$student_links %>%
    left_join(
      distribution_info$reviewer_assignments %>%
        group_by(reviewer_student_id) %>%
        summarise(review_assignments = paste(glue("{reviewed_student_name}: {review_url}"), collapse = "\n"),
                 .groups = "drop"),
      by = c("student_id" = "reviewer_student_id")
    ) %>%
    mutate(review_assignments = ifelse(is.na(review_assignments), "None assigned", review_assignments))
  
  write_csv(email_data, file.path(output_dir, "email_merge_data.csv"))
  
  cat(glue("Email templates generated in {output_dir}\n"))
}