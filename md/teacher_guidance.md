# Teacher Guide: Implementing Code Peer Review with GitHub

## Overview

This guide provides instructions for using the `codeinput` R package to automate the setup and management of code peer review assignments on GitHub.
The system integrates with Moodle for familiar student submission and leverages GitHub's collaborative features for peer review.

## Prerequisites

- GitHub account with ability to create organizations
- Access to module Moodle page
- R and RStudio installed
- Student list with GitHub usernames
- Assessment materials and marking criteria prepared


## Quick Start

### Step 1: Installation and Setup (One-Time)

* **Install the `codeinput` package**:

```r
# Install devtools if you don't have it
if (!requireNamespace("devtools", quietly = TRUE)) {
    install.packages("devtools")
}

# Install the codeinput package from GitHub
devtools::install_github("https://github.com/stats-ucl/code-peer-review")
```

* **Run the setup function**: Once installed, load the package and run the setup function.
This will install required packages, guide you through GitHub authentication, and create the necessary folder structure.
```r
library(codeinput)
run_setup()
```

This automated setup will:
- Install required R packages
- Guide you through GitHub token creation
- Create necessary folder structure
- Generate sample configuration files
- Validate your setup

### 2. Prepare Your Data

**Create your student list (`student_list.csv`):**

```csv
student_id,github_username,ucl_email,name
12345,alice_github,alice.smith@ucl.ac.uk,Alice Smith
12346,bob_jones,bob.jones@ucl.ac.uk,Bob Jones
12347,carol_white,carol.white@ucl.ac.uk,Carol White
```

**Organize student submissions:**
Download submissions from Moodle and organize them in folders:
```
submissions/
├── 12345/
│   ├── analysis.R
│   └── data_cleaning.R
├── 12346/
│   ├── analysis.R
│   └── visualization.R
```

### 3. Run the Automation

**Configure the main script:**

Edit these variables in `main_automation_script.R`:

```r
ORG_NAME <- "UCL-StatSci-STAT0001-2025"      # Your GitHub organization
ASSIGNMENT_NAME <- "assignment-1"            # Current assignment
LOCAL_SUBMISSIONS_PATH <- "submissions/"     # Path to submissions
```

**Execute the automation:**
```r
source("main_automation_script.R")
```

**What happens automatically:**
- ✅ Creates private repositories for each student
- ✅ Sets up reviewer branches and issue templates
- ✅ Uploads all student files
- ✅ Randomly assigns peer reviewers (2 per student)
- ✅ Sets repository permissions
- ✅ Generates email templates and distribution URLs

### 4. Distribute and Monitor

The script generates several files:

- `student_repo_links.csv` - Repository URLs for each student
- `email_templates/` - Personalized emails for each student
- `reviewer_assignments.csv` - Complete assignment matrix

**Send emails to students:**
Use the generated email templates or import the CSV data into your email system for mail merge.

### 5. Monitor Progress

**Track completion in real-time:**
```r
source("monitor_progress.R")
report <- run_progress_check()
```

This script provides:

- Completion rates across all students
- Visual progress charts
- Detailed analytics
- Automated reminder emails for incomplete reviews



The section below is a very detailed explanation of the workflow.
If you have any trouble executing the above procedure, please refer to the section below, and the `README.md` document under the setup folder.

## Detailed Process Walkthrough

### GitHub Organization Setup

**Create your organization (one-time):**

1. Go to https://github.com/settings/organizations
2. Click "New organization"
3. Choose organization name: `UCL-[Department]-[Module]-[Year]`
4. Set to "Private" initially
5. Add description and contact information

**The automation handles all repository creation and configuration.**

### Assessment Preparation

**Before running automation, prepare:**

**Issue Templates** (automatically created):
The scripts create structured peer review templates with sections for:
- Code quality assessment
- Correctness evaluation
- Constructive feedback
- Learning reflections

**Marking Criteria Integration:**
Customize the issue template in `github_functions.R` to align with your specific marking criteria:
```r
# Edit the peer_review_template variable to match your assessment goals
```

**Assignment Instructions:**
Prepare clear instructions that reference:
- Learning objectives for peer review
- Timeline and deadlines
- Technical support resources
- Assessment weighting (if applicable)

### Student Data Collection

**Collect GitHub usernames efficiently:**

**Option 1: Moodle Survey**
Create a Moodle survey with:
- "GitHub username" text field
- Instructions for creating GitHub accounts
- Link to GitHub Education benefits

**Option 2: Submission Requirement**
Include GitHub username as part of the assignment submission requirements.

**Option 3: Lab Session Collection**
Collect usernames during the first computer lab session.

### File Transfer Workflow

**Automated Process (Recommended):**
```r
# Place files in submissions/[student_id]/ folders
# Run the main automation script
source("main_automation_script.R")
```

**Manual Process (Backup Method):**
If automation fails, you can still upload files manually:
1. Create repositories individually
2. Upload files through GitHub web interface
3. Set permissions manually
4. Generate assignment lists manually

### Managing the Review Process

**Monitoring Student Engagement:**
```r
# Run daily or weekly progress checks
source("monitor_progress.R")
run_progress_check()

# Generates:
# - Completion rate summaries
# - Individual student progress
# - Reminder emails for laggards
```

**Facilitating Quality Reviews:**
- Monitor issue creation across repositories
- Look for generic or unconstructive feedback
- Highlight examples of excellent reviews to the class
- Provide additional guidance if review quality is poor

### Assessment Integration

**Assessing Peer Review Participation:**

**Quantitative Measures:**
- Completion of required review templates
- Timeliness of feedback submission
- Engagement with issue discussions

**Qualitative Assessment:**
```r
# Use monitoring script to extract review content
# Assess based on:
# - Constructiveness of feedback
# - Specificity of observations
# - Helpful suggestions provided
# - Professional communication tone
```


### Troubleshooting
See [troubleshooting](md/troublshooting.md) file.


### Advanced Features

**Customizing Review Assignments:**
Edit `file_management.R` to modify reviewer assignment logic:
```r
# Change number of reviewers per student
assign_peer_reviewers(students, reviews_per_student = 3)

# Implement stratified assignment (e.g., by ability level)
# Custom logic can be added to the assign_peer_reviewers function
```

**Integration with Continuous Assessment:**
- Use repository activity for participation grades
- Track improvement over multiple assignments
- Monitor collaborative discussion quality

**Scaling for Large Classes:**
The automation scripts handle classes up to 200+ students efficiently:
- Batch processing minimizes API rate limits
- Progress monitoring scales automatically
- Email generation handles large volumes

### Alternative Workflows

**For Smaller Classes (<20 students):**
Consider having all students review all submissions for maximum learning.

**For Advanced Students:**
- Enable pull request reviews in addition to issues
- Encourage code improvement suggestions
- Allow collaborative debugging sessions

**For Assessment-Heavy Modules:**
- Use multiple rounds of peer review
- Implement peer review of peer reviews (meta-review)
- Create portfolio-based assessment incorporating peer feedback



## Evaluation and Improvement

### Data Collection

**Automated Metrics:**
```r
# Progress monitoring provides:
# - Completion rates
# - Engagement timing
# - Issue/PR creation patterns
# - Student interaction levels
```

**Student Feedback:**
- Post-assignment surveys about GitHub experience
- Focus groups on peer review value
- Comparison with traditional feedback methods

**Learning Outcomes Assessment:**
- Code quality improvement over semester
- Development of collaborative skills
- Professional tool proficiency

### Iterative Improvements

**Based on Student Feedback:**
- Adjust issue template questions
- Modify review assignment algorithms
- Update student guidance materials
- Refine technical support processes

**Based on Teaching Observations:**
- Identify common student misconceptions
- Adjust scaffold levels for GitHub introduction
- Modify assessment weightings
- Update marking criteria


### Approximate Time Investment

**Initial Setup (First Time):**
- Script configuration: 30 minutes
- GitHub organization setup: 15 minutes
- Student data preparation: 45 minutes
- **Total: ~1.5 hours**

**Per Assignment (Ongoing):**
- File organization: 15 minutes
- Running automation: 5 minutes
- Monitoring and reminders: 10 minutes weekly
- **Total: ~20 minutes + weekly monitoring**


