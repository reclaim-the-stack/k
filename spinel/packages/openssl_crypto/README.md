# openssl_crypto for Spinel

The part of OpenSSL's API that SCRAM-SHA-256 authentication needs, for [Spinel](https://github.com/matz/spinel) compiled programs which shouldn't depend on the system libssl. Spinel's own `openssl` package links libssl as soon as it's required, so this provides the same API over Spinel's built-in crypto instead:

- `OpenSSL::Digest.new("SHA256")` with `#update` / `#<<`, `#digest`, `#digest_length`, `#block_length` and `#name`
- `OpenSSL::HMAC.digest("sha256", key, data)`
- `OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iterations, length, digest)`, for lengths up to 64 bytes

Only SHA-256 is supported, other digests raise `ArgumentError`. Inputs and outputs are binary safe.

Under CRuby, `require "openssl_crypto"` requires the real OpenSSL instead, which makes `spin test` compare this implementation against it.

## Testing

```sh
spin test
```
