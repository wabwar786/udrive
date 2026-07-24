# Phase 7 Validation

Static checks completed in the generation environment:

- C# brace balance
- Project XML parsing
- JSON parsing
- Ordered embedded SQL migrations
- PostgreSQL/PostGIS schema review
- EF Core snake_case naming alignment
- Railway Dockerfile review
- GitHub Actions path review

The generation environment does not include the .NET SDK, so final restore/build validation will run through the included GitHub Action after the files are pushed.
