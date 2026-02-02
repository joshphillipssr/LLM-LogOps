# Security Guidelines

## Sensitive Data Protection

This repository is designed to work with **real production security logs**. Follow these guidelines to prevent data exposure:

### 🔴 Never Commit:

1. **Credential files**
   - `.env` (already in .gitignore)
   - Any files containing `AZURE_CLIENT_SECRET`, API keys, or tokens

2. **Report/Log files**
   - `reports/**/*.json` (already in .gitignore)
   - These files contain real user data, IPs, device IDs, and other sensitive information

3. **Real tenant/organizational data**
   - User principal names (emails)
   - Tenant IDs (if sensitive to your organization)
   - Device identifiers
   - IP addresses
   - Geographic location data

### ✅ Safe to Commit:

- Scripts and code (as long as they don't contain hardcoded credentials)
- `.env.example` with placeholder values only
- Documentation
- Schemas and templates
- Empty `.gitkeep` files for directory structure

### Best Practices:

1. **Use .env for all secrets** - Never hardcode credentials in scripts
2. **Review before pushing** - Use `git status` and `git diff --cached` to verify no sensitive files are staged
3. **Sanitize examples** - If you need to commit example outputs, use synthetic/anonymized data only
4. **Check git history** - If you accidentally commit sensitive data:
   ```bash
   # Remove from git but keep local file
   git rm --cached path/to/sensitive-file.json
   
   # If already pushed, you need to purge history
   git filter-repo --path path/to/sensitive-file.json --invert-paths
   ```

### Current Protection Status:

- ✅ `.env` is protected via .gitignore
- ✅ `reports/*` is excluded via .gitignore  
- ✅ No hardcoded secrets in code
- ✅ `.env.example` contains only placeholders

### For Public Repositories:

Before making this repo public, ensure:
- [ ] No real tenant data in commit history
- [ ] No real user emails/IDs in any committed files
- [ ] No IP addresses or geographic locations exposed
- [ ] All example data is synthetic or fully anonymized
- [ ] `.gitignore` properly excludes all report directories
- [ ] GitHub secret scanning alerts are enabled
