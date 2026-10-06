# OpenSSL's Digest, HMAC and PKCS5 for SHA-256, over Spinel's built-in crypto, see README.md.

unless RUBY_ENGINE == "spinel"
  require "openssl"
  return
end

module OpenSSLCrypto
  native_lib "openssl_crypto"
  native_func :sha256, [:string], :cbinstr, "sp_crypto_sha256_bin"
  native_func :hmac_sha256, [:string, :string], :cbinstr, "sp_crypto_hmac_sha256_bin"
  native_func :pbkdf2_sha256_b64url, [:string, :string, :int, :int], :cstring, "sp_crypto_pbkdf2_sha256_b64url_len"
  native_func :b64url_decode, [:string], :cbinstr, "sp_crypto_b64url_decode"

  def self.verify_sha256!(name)
    return if name.to_s.casecmp?("sha256")

    raise ArgumentError, "openssl_crypto only supports SHA256, not #{name}"
  end
end

module OpenSSL
  class OpenSSLError < StandardError; end

  class Digest
    def initialize(name, data = nil)
      OpenSSLCrypto.verify_sha256!(name)
      @data = data.to_s.dup
    end

    def name = "SHA256"
    def digest_length = 32
    def block_length = 64

    def update(data)
      @data << data
      self
    end
    alias << update

    def digest(data = nil)
      OpenSSLCrypto.sha256(data.nil? ? @data : data)
    end
  end

  module HMAC
    def self.digest(digest, key, data)
      OpenSSLCrypto.verify_sha256!(digest.is_a?(String) ? digest : digest.name)
      OpenSSLCrypto.hmac_sha256(key, data)
    end
  end

  module PKCS5
    def self.pbkdf2_hmac(password, salt, iterations, length, digest)
      OpenSSLCrypto.verify_sha256!(digest.is_a?(String) ? digest : digest.name)
      raise ArgumentError, "openssl_crypto derives at most 64 bytes" unless length.between?(1, 64)

      OpenSSLCrypto.b64url_decode(OpenSSLCrypto.pbkdf2_sha256_b64url(password, salt, iterations, length))
    end
  end
end
