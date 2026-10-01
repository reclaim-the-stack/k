require "openssl_crypto"

# The primitives behind SCRAM-SHA-256 (RFC 7677), as k's Postgres proxy uses them, over binary
# inputs including NUL bytes
salt = "\x00\x01salt\x00\xff".b
digest = OpenSSL::Digest.new("SHA256")
p digest.digest_length
salted = OpenSSL::PKCS5.pbkdf2_hmac("pässword", salt, 4096, digest.digest_length, digest)
p salted.unpack1("H*")
client_key = OpenSSL::HMAC.digest("sha256", salted, "Client Key")
p client_key.unpack1("H*")
p OpenSSL::Digest.new("SHA256").update(client_key).digest.unpack1("H*")
p OpenSSL::Digest.new("SHA256").update("a\x00").update("b").digest.unpack1("H*")
p OpenSSL::HMAC.digest("sha256", "", "").unpack1("H*")
p OpenSSL::PKCS5.pbkdf2_hmac("password", "salt", 1, 64, OpenSSL::Digest.new("SHA256")).unpack1("H*")
