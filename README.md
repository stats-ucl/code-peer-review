# GitHub Code Peer Review Automation Scripts

This collection of R scripts automates the setup and management of code peer review assignments using GitHub repositories integrated with Moodle submissions.

## Overview

The system allows you to:
- Automatically create private GitHub repositories for each student
- Upload student code submissions from local folders
- Randomly assign peer reviewers
- Set up structured peer review templates
- Monitor progress and send reminders
- Generate distribution emails and reports



## Prerequisites

### Software Requirements

- R (≥ 4.0)
- Required R packages (automatically installed by setup script):
  - `gh` (GitHub API)
  - `dplyr`, `readr`, `purrr` (data manipulation)
  - `glue` (string interpolation)
  - `ggplot2`, `lubridate`, `scales` (visualization and dates)

### GitHub Setup

1. **GitHub Organization**: Create or have access to a GitHub organization
2. **Personal Access Token**: Create a token with these permissions:
   - `repo` (full control of private repositories)
   - `admin:org` (full control of organizations and teams)
   - `user` (update user data)

### Data Requirements

1. **Student List**: CSV file with student IDs, GitHub usernames, emails, and names
2. **Submission Files**: Student code files organized in folders by student ID



## Quick Start

### 1. Initial Setup
```r
# Run the setup script first
source("setup_config.R")
run_setup()
```

This will:
- Install required R packages
- Help you set up GitHub authentication
- Create necessary directory structure
- Generate sample configuration files

### 2. Prepare Your Data

**Student List (`student_list.csv`):**
```csv
student_id,github_username,ucl_email,name
12345,alice_github,alice@ucl.ac.uk,Alice Smith
12346,bob_github,bob@ucl.ac.uk,Bob Jones
```

**Submission Files:**
Place each student's submitted files in `submissions/[student_id]/` folders:
```
submissions/
├── 12345/
│   ├── analysis.R
│   └── report.Rmd
├── 12346/
│   ├── analysis.R
│   └── data_cleaning.R
```

### 3. Run Main Automation
```r
# Configure and run the main script
source("main_automation_script.R")
```

### 4. Monitor Progress
```r
# Check review completion status
source("monitor_progress.R")
report <- run_progress_check()
```



## File Structure

```
project/
├── setup_config.R              # Initial setup and configuration
├── main_automation_script.R    # Main orchestration script
├── github_functions.R          # GitHub API helper functions
├── file_management.R           # File upload and assignment functions
├── monitor_progress.R          # Progress tracking and reporting
├── student_list.csv            # Student information (you create this)
├── submissions/                # Student submission folders
│   ├── 12345/
│   └── 12346/
├── email_templates/            # Generated email templates
├── progress_reports/           # Progress tracking outputs
└── reminders/                  # Reminder emails for incomplete reviews
```

## Script Details

### `setup_config.R`
**Purpose:** Initial environment setup and configuration validation

**Key Functions:**
- `run_setup()` - Complete setup process
- `setup_github_token()` - GitHub authentication setup
- `validate_configuration()` - Check all requirements
- `test_github_connection()` - Verify GitHub access

**Usage:**
```r
source("setup_config.R")
run_setup()  # First time setup
validate_configuration()  # Check before running main script
```

### `main_automation_script.R`
**Purpose:** Main orchestration script that sets up the entire peer review system

**What it does:**
1. Creates GitHub repositories for each student
2. Sets up repository structure (branches, templates)
3. Uploads student files from local folders
4. Randomly assigns peer reviewers (2 per student by default)
5. Sets repository permissions
6. Generates distribution emails and URLs

**Configuration variables:**
```r
ORG_NAME <- "UCL-StatSci-STAT001-2025"
ASSIGNMENT_NAME <- "assignment-1"
LOCAL_SUBMISSIONS_PATH <- "submissions/"
```

### `github_functions.R`
**Purpose:** GitHub API operations and repository management

**Key Functions:**
- `create_student_repo()` - Create private repository
- `setup_repo_structure()` - Create branches and templates
- `set_reviewer_permissions()` - Assign collaborator access
- `get_repo_info()` - Retrieve repository URLs

### `file_management.R`
**Purpose:** File handling and peer review assignment logic

**Key Functions:**
- `upload_student_files()` - Upload files from local folders
- `assign_peer_reviewers()` - Random reviewer assignment
- `generate_distribution_info()` - Create URLs and assignment data
- `generate_email_templates()` - Create notification emails

### `monitor_progress.R`
**Purpose:** Track completion and generate progress reports

**Key Functions:**
- `monitor_review_progress()` - Check completion status
- `generate_progress_report()` - Create summary statistics
- `create_progress_visualizations()` - Generate charts
- `generate_reminder_emails()` - Send completion reminders



## Configuration

### Environment Variables
Set your GitHub token as an environment variable:

**Option 1: .Renviron file (recommended)**
```
GITHUB_TOKEN=your_token_here
```

**Option 2: Session variable**
```r
Sys.setenv(GITHUB_TOKEN = "your_token_here")
```

### Script Configuration
Edit these variables in `main_automation_script.R`:
```r
ORG_NAME <- "UCL-StatSci-STAT001-2025"      # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"            # Assignment identifier
LOCAL_SUBMISSIONS_PATH <- "submissions/"     # Path to submission folders
```



## Workflow

### For Teachers

1. **Setup** (one-time):
   ```r
   source("setup_config.R")
   run_setup()
   ```

2. **Prepare data**:
   - Export student list from UCL systems
   - Download submissions from Moodle
   - Organize files in `submissions/` folders

3. **Run automation**:
   ```r
   source("main_automation_script.R")
   ```

4. **Distribute access**:
   - Send generated emails to students
   - Share repository URLs

5. **Monitor progress**:
   ```r
   source("monitor_progress.R")
   run_progress_check()
   ```

### For Students

Students receive:
- Link to their personal repository
- Instructions for accessing peer review assignments
- Email notifications when reviews are submitted
- Links to review other students' code

## Output Files

The scripts generate several files for distribution and monitoring:

- `student_repo_links.csv` - Repository URLs for each student
- `reviewer_assignments.csv` - Who reviews whom
- `teacher_summary.csv` - Complete overview for instructors
- `email_templates/` - Individual email files for each student
- `progress_check_[date].csv` - Progress monitoring data
- `progress_reports/` - Visualization and analysis files



## Troubleshooting

### Common Issues

**GitHub Authentication Fails**
- Check your token has correct permissions
- Verify token is set in environment
- Test with `test_github_connection()`

**Repository Creation Fails**
- Ensure you have admin access to the organization
- Check organization name spelling
- Verify API rate limits haven't been exceeded

**File Upload Fails**
- Check file paths and permissions
- Verify files aren't too large (GitHub has 100MB limit)
- Ensure file formats are supported

**Students Can't Access Repositories**
- Verify GitHub usernames are correct
- Check repository permissions were set
- Confirm students have GitHub accounts

### Error Recovery

If the main script fails partway through:
1. Check the console output for specific errors
2. Fix the underlying issue
3. Re-run from the main script - it will skip already-created repositories
4. Use `validate_configuration()` to check setup

### Getting Help

1. Check the GitHub API documentation: https://docs.github.com/en/rest
2. Review R package documentation: `?gh`, `?dplyr`
3. Validate your configuration: `validate_configuration()`
4. Test individual functions with sample data

## Security Considerations

- **Never commit your GitHub token** to version control
- Use `.gitignore` to exclude sensitive files
- Keep student data files local and private
- Regularly rotate GitHub tokens
- Monitor organization access and remove unused collaborators



## Customization

### Changing Review Template
Edit the template in `github_functions.R` in the `create_github_templates()` function.

### Adjusting Reviewer Assignments
Modify the assignment logic in `file_management.R` in the `assign_peer_reviewers()` function.

### Adding Notification Features
Extend the email generation functions in `file_management.R` to integrate with your email system.
