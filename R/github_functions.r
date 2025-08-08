# GitHub API Helper Functions
# Contains all GitHub-specific operations for the peer review system

# Check GitHub authentication
check_github_auth <- function() {
  tryCatch({
    user_info <- gh("GET /user")
    cat(glue("Authenticated as: {user_info$login}\n"))
    return(TRUE)
  }, error = function(e) {
    stop("GitHub authentication failed. Please set GITHUB_TOKEN environment variable.")
  })
}

# Validate student data format
validate_student_data <- function(students) {
  required_cols <- c("student_id", "github_username", "ucl_email", "name")
  missing_cols <- setdiff(required_cols, names(students))
  
  if (length(missing_cols) > 0) {
    stop(glue("Missing required columns: {paste(missing_cols, collapse=', ')}"))
  }
  
  # Check for missing GitHub usernames
  missing_github <- students %>% filter(is.na(github_username) | github_username == "")
  if (nrow(missing_github) > 0) {
    warning(glue("Students missing GitHub usernames: {paste(missing_github$name, collapse=', ')}"))
  }
  
  cat(glue("Validated data for {nrow(students)} students\n"))
}

# Create a repository for a student
create_student_repo <- function(repo_name, github_username, org_name) {
  tryCatch({
    # Create repository
    repo <- gh("POST /orgs/{org}/repos", 
               org = org_name,
               name = repo_name,
               description = glue("Code submission repository for {github_username}"),
               private = TRUE,
               auto_init = TRUE)
    
    cat(glue("Created repository: {repo_name}\n"))
    return(TRUE)
  }, error = function(e) {
    warning(glue("Failed to create repository {repo_name}: {e$message}"))
    return(FALSE)
  })
}

# Set up repository structure (branches, templates, etc.)
setup_repo_structure <- function(repo_name, org_name) {
  tryCatch({
    # Get main branch SHA
    main_branch <- gh("GET /repos/{owner}/{repo}/git/ref/heads/main",
                      owner = org_name, repo = repo_name)
    main_sha <- main_branch$object$sha
    
    # Create reviewer branches
    gh("POST /repos/{owner}/{repo}/git/refs",
       owner = org_name, repo = repo_name,
       ref = "refs/heads/reviewer-1",
       sha = main_sha)
    
    gh("POST /repos/{owner}/{repo}/git/refs",
       owner = org_name, repo = repo_name,
       ref = "refs/heads/reviewer-2", 
       sha = main_sha)
    
    # Create .github directory structure
    create_github_templates(repo_name, org_name)
    
    # Create initial folder structure
    create_folder_structure(repo_name, org_name)
    
    cat(glue("Set up structure for: {repo_name}\n"))
    return(TRUE)
  }, error = function(e) {
    warning(glue("Failed to setup structure for {repo_name}: {e$message}"))
    return(FALSE)
  })
}

# Create GitHub issue templates
create_github_templates <- function(repo_name, org_name) {
  # Peer review issue template
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

  # Create the template file
  gh("PUT /repos/{owner}/{repo}/contents/.github/ISSUE_TEMPLATE/peer-review.md",
     owner = org_name, repo = repo_name,
     message = "Add peer review issue template",
     content = base64encode(charToRaw(peer_review_template)))
}

# Create initial folder structure
create_folder_structure <- function(repo_name, org_name) {
  # Create README for assignment
  readme_content <- glue('# Code Assignment Repository

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

  gh("PUT /repos/{owner}/{repo}/contents/README.md",
     owner = org_name, repo = repo_name,
     message = "Add initial README",
     content = base64encode(charToRaw(readme_content)))
  
  # Create submission folder with placeholder
  gh("PUT /repos/{owner}/{repo}/contents/submission/.gitkeep",
     owner = org_name, repo = repo_name, 
     message = "Create submission folder",
     content = base64encode(charToRaw("")))
}

# Set reviewer permissions for a repository
set_reviewer_permissions <- function(repo_name, student_id, reviewer_assignments, org_name) {
  student_reviewers <- reviewer_assignments %>%
    filter(reviewed_student_id == student_id)
  
  results <- map_dfr(1:nrow(student_reviewers), function(i) {
    reviewer <- student_reviewers[i, ]
    
    tryCatch({
      # Add collaborator with write permission
      gh("PUT /repos/{owner}/{repo}/collaborators/{username}",
         owner = org_name, repo = repo_name,
         username = reviewer$reviewer_github_username,
         permission = "write")
      
      cat(glue("Added {reviewer$reviewer_github_username} as collaborator to {repo_name}\n"))
      
      tibble(
        repo_name = repo_name,
        reviewer_username = reviewer$reviewer_github_username,
        success = TRUE,
        error = NA
      )
    }, error = function(e) {
      warning(glue("Failed to add {reviewer$reviewer_github_username} to {repo_name}: {e$message}"))
      
      tibble(
        repo_name = repo_name,
        reviewer_username = reviewer$reviewer_github_username,
        success = FALSE,
        error = e$message
      )
    })
  })
  
  return(results)
}

# Get repository URLs and information
get_repo_info <- function(repo_name, org_name) {
  tryCatch({
    repo <- gh("GET /repos/{owner}/{repo}", owner = org_name, repo = repo_name)
    
    list(
      html_url = repo$html_url,
      clone_url = repo$clone_url,
      issues_url = glue("{repo$html_url}/issues"),
      pulls_url = glue("{repo$html_url}/pulls")
    )
  }, error = function(e) {
    warning(glue("Failed to get info for {repo_name}: {e$message}"))
    list(html_url = NA, clone_url = NA, issues_url = NA, pulls_url = NA)
  })
}

# Check repository access for a user
check_repo_access <- function(repo_name, username, org_name) {
  tryCatch({
    collab <- gh("GET /repos/{owner}/{repo}/collaborators/{username}",
                 owner = org_name, repo = repo_name, username = username)
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}