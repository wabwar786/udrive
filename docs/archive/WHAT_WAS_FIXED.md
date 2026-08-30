# What Was Fixed

The latest portal changed attachment loading from the original stored
`fileUrl` to only the new document-ID lookup endpoint.

Some existing attachments were already working through their stored
URL. The new document-ID lookup incorrectly reported them as missing.

The preview now tries both routes:

1. Original stored `fileUrl`.
2. New document-ID endpoint as fallback.

The Admin bearer token is sent only to the configured API origin and is
never forwarded to a different external URL.
