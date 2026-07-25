# Swagger 500 Fix

The Swagger document previously returned HTTP 500 because multipart file
endpoints used an unsupported `IFormFile` binding pattern.

The update:

- Adds `[Consumes("multipart/form-data")]` to driver and vehicle document
  upload endpoints.
- Removes the redundant `[FromForm]` attribute from `IFormFile`.
- Uses fully qualified custom schema IDs.
- Enables non-nullable reference type support.

After deploying the API, this URL must return JSON:

```text
https://udrive-api-production.up.railway.app/swagger/v1/swagger.json
```

If it still returns HTTP 500, inspect the API application log using the
trace ID. Do not deploy the Admin portal until the API build and migration
are healthy.
