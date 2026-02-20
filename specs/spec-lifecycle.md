# Specification Lifecycle

## Overview

Specifications are the source of truth for desired project behavior. They define what the system should do, and the Ralph loop reconciles code with specs through plan and build modes.

## Core Principle

**Specs represent the target state of the project** - both completed features and planned additions.

## Spec Evolution Rules

### When to Update Specs

#### 1. Adding New Features
Create a new spec or update existing spec to describe the desired behavior:
```bash
# Create new spec
vim specs/new-feature.md

# Run plan mode to generate tasks
ralph plan

# Run build mode to implement
ralph build
```

#### 2. Changing Existing Behavior
Update the spec to reflect the new desired behavior:
```bash
# Update spec with new requirements
vim specs/existing-feature.md

# Re-run plan mode to detect changes
ralph plan

# Build mode will implement the changes
ralph build
```

#### 3. Refactoring
- **Observable changes** (API, behavior, constraints): Update spec
- **Internal changes** (code structure, performance): No spec change needed unless constraints are documented

#### 4. Discovered Drift
When code doesn't match specs:
- **Intended behavior**: Update spec to match reality
- **Unintended behavior**: Keep spec as-is; plan mode will generate fix tasks

### When NOT to Update Specs

- Implementation details (unless they're constraints)
- Internal code organization
- Performance optimizations (unless performance requirements are specified)
- Bug fixes (unless they reveal spec gaps)

## Spec Format

### Structure

Each spec should be:
- **One file per feature/component**
- **Written in Markdown**
- **Human-readable and agent-parseable**
- **Version controlled with the project**

### Recommended Sections

```markdown
# Feature Name

## Purpose
What this feature does and why it exists.

## Requirements
Functional requirements - what the system must do.

## Behavior
Detailed behavior specifications.

## API/Interface
Public interfaces, endpoints, function signatures.

## Constraints
Performance, security, compatibility requirements.

## Dependencies
External services, libraries, other features.

## Testing
How to verify the feature works correctly.

## Examples
Usage examples, sample inputs/outputs.
```

### Example Spec

```markdown
# User Authentication

## Purpose
Provide secure user authentication using JWT tokens for the REST API.

## Requirements
- Users must be able to register with email and password
- Users must be able to log in with email and password
- API endpoints must be protected by JWT authentication
- Tokens must expire after 24 hours
- Passwords must be hashed using bcrypt

## Behavior

### Registration
- POST /api/register
- Accepts: { email, password }
- Validates email format
- Validates password strength (min 8 chars, 1 uppercase, 1 number)
- Returns: { token, user }

### Login
- POST /api/login
- Accepts: { email, password }
- Returns: { token, user }
- Returns 401 if credentials invalid

### Protected Endpoints
- Require Authorization header: "Bearer <token>"
- Return 401 if token missing or invalid
- Return 403 if token expired

## API/Interface

### POST /api/register
Request:
```json
{
  "email": "user@example.com",
  "password": "SecurePass123"
}
```

Response (201):
```json
{
  "token": "eyJhbGc...",
  "user": {
    "id": "123",
    "email": "user@example.com"
  }
}
```

### POST /api/login
Request:
```json
{
  "email": "user@example.com",
  "password": "SecurePass123"
}
```

Response (200):
```json
{
  "token": "eyJhbGc...",
  "user": {
    "id": "123",
    "email": "user@example.com"
  }
}
```

## Constraints
- JWT secret must be stored in environment variable JWT_SECRET
- Bcrypt cost factor: 10
- Token expiry: 24 hours
- Must use passport.js for authentication middleware

## Dependencies
- passport.js
- passport-jwt
- bcrypt
- jsonwebtoken

## Testing
- Unit tests for password hashing
- Integration tests for registration endpoint
- Integration tests for login endpoint
- Integration tests for protected endpoint access
- Test token expiry behavior

## Examples

### Registering a User
```bash
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"SecurePass123"}'
```

### Accessing Protected Endpoint
```bash
curl http://localhost:3000/api/profile \
  -H "Authorization: Bearer eyJhbGc..."
```
```

## Spec Maintenance

### Regular Review
Periodically review specs to ensure they:
- Reflect current requirements
- Are up to date with implemented features
- Don't contain obsolete information

### Version Control
- Commit spec changes with clear messages
- Specs evolve with the project
- Git history shows requirement evolution

### Collaboration
- Humans write/edit specs
- Agents read specs to generate plans
- Specs are the contract between human intent and agent implementation

## Plan Mode Integration

Plan mode uses specs to:
1. **Understand desired state** - Read all specs
2. **Compare to current state** - Analyze code
3. **Identify gaps** - Find missing or incorrect implementations
4. **Generate tasks** - Create ordered work items to close gaps

### Workflow

```
Human updates spec → Plan mode detects change → Tasks generated → Build mode implements
```

## Best Practices

### Be Specific
- Clear, unambiguous requirements
- Concrete examples
- Explicit constraints

### Be Complete
- Cover all aspects of the feature
- Include edge cases
- Document error handling

### Be Maintainable
- One feature per spec
- Logical organization
- Easy to update

### Be Testable
- Define success criteria
- Specify test scenarios
- Include verification steps

## Anti-Patterns

### ❌ Implementation Details in Specs
Don't specify:
- Variable names
- Internal function structure
- Code organization

Unless they're part of a public API or explicit constraint.

### ❌ Outdated Specs
Don't let specs drift from reality. Update them when requirements change.

### ❌ Vague Requirements
Avoid:
- "Should be fast"
- "User-friendly interface"
- "Handle errors appropriately"

Be specific about what these mean.

### ❌ Mixing Multiple Features
Keep specs focused. One feature per spec makes them easier to:
- Understand
- Update
- Implement
- Test

## Summary

Specs are living documents that:
- Define desired behavior
- Guide agent planning
- Evolve with the project
- Are maintained by humans
- Drive the Ralph loop

Update specs when requirements change, and let the Ralph loop handle implementation.
