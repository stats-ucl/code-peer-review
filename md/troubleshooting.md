# Troubleshooting

## Common Issues

### GitHub Authentication Fails:

Ensure your GitHub PAT has the correct permissions.

Verify that the token is correctly set as an environment variable.

Use `codeinput::test_github_connection()` to test your connection.

### Repository Creation Fails:

Confirm that you have administrative access to the GitHub organization.

Check for typos in the organization name.

Be mindful of GitHub API rate limits.

### File Upload Fails:

Check file paths and permissions.

Ensure that file sizes are within GitHub's limits (100MB per file).

### Students Can't Access Repositories:

Verify that the GitHub usernames in your student list are correct.

Confirm that students have accepted the invitation to the repository.

### Error Recovery

If the main script fails midway:

Review the console output for specific error messages.

Address the underlying issue.

Re-run the script. It is designed to skip steps that have already been completed successfully.

Use `codeinput::validate_configuration()` to check your setup.

### Security Considerations

Never commit your GitHub token or any other sensitive credentials to version control.

Use a `.gitignore` file to exclude sensitive files and folders.

Keep student data files private and secure.

Regularly rotate your GitHub tokens to enhance security.

Monitor access to your GitHub organization and remove collaborators who no longer need access.


### Script Failures

```r
# Check configuration
source("setup_config.R")
validate_configuration()

# Test GitHub connection
test_github_connection()
```

### Student Access Problems

- Verify GitHub usernames in `student_list.csv`
- Check repository permissions in GitHub organization
- Use monitoring script to identify access issues

### File Upload Issues

- Check file sizes (GitHub limit: 100MB per file)
- Verify file paths in submissions folders
- Review console output for specific error messages

### Incomplete Reviews

```r
# Generate targeted reminders
source("monitor_progress.R")
run_progress_check()  # Creates reminder emails automatically
```
