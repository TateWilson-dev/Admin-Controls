## Testing and Quality Gate Requirement

Claude must test changes before committing or pushing.

Claude must follow this process for every code change:

1. Work on a feature branch.

2. Before editing, inspect the project and identify the test commands:
   - If `package.json` exists, check scripts such as `test`, `lint`, `typecheck`, and `build`.
   - If Python files exist, look for `pytest`, `unittest`, `requirements.txt`, `pyproject.toml`, or `tox.ini`.
   - If `.csproj` or `.sln` files exist, use `dotnet test` and `dotnet build`.
   - If Go files exist, use `go test ./...`.
   - If Java/Maven exists, use `mvn test`.
   - If Gradle exists, use `gradle test` or `./gradlew test`.
   - If no test framework exists, explain that no automated tests were found and run a basic smoke/build check where possible.

3. After making changes, run the relevant checks locally before committing.

4. At minimum, Claude must run:
   ```bash
   git status
   git diff
   gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1
