require 'ssrf_filter'

module SafeFetch
  DEFAULT_ALLOWED_CONTENT_TYPE_PREFIXES = %w[image/ video/].freeze
  DEFAULT_ALLOWED_CONTENT_TYPES = [].freeze
  DEFAULT_SENSITIVE_HEADERS = %w[authorization cookie proxy-authorization].freeze
  DEFAULT_OPEN_TIMEOUT = 2
  DEFAULT_READ_TIMEOUT = 20
  DEFAULT_MAX_BYTES_FALLBACK_MB = 40

  Result = Data.define(:tempfile, :filename, :content_type) do
    def original_filename
      filename
    end
  end

  class Error < StandardError; end
  class InvalidUrlError < Error; end
  class UnsafeUrlError < Error; end
  class FetchError < Error; end
  class HttpError < Error; end
  class FileTooLargeError < Error; end
  class UnsupportedContentTypeError < Error; end
  class UnsupportedMethodError < Error; end
end

require_relative 'safe_fetch/request_options'
require_relative 'safe_fetch/fetcher'

module SafeFetch
  def self.fetch(url, **, &)
    raise ArgumentError, 'block required' unless block_given?

    # [2026-05-07 abckxopen-fork] require_relative defensivo dentro do método —
    # em parallel CI partition Zeitwerk pode dropar SafeFetch::Fetcher entre
    # o top-level require (linhas 27-28) e a chamada do método. require é
    # idempotente (no-op se já carregado). Pinning explícito do namespace
    # SafeFetch:: blinda contra reload. Mesma classe do upstream #14139.
    require_relative 'safe_fetch/request_options'
    require_relative 'safe_fetch/fetcher'

    SafeFetch::Fetcher.new(SafeFetch::RequestOptions.new(url: url, **)).fetch(&)
  rescue SsrfFilter::InvalidUriScheme, URI::InvalidURIError => e
    raise InvalidUrlError, e.message
  rescue SsrfFilter::Error, Resolv::ResolvError => e
    raise UnsafeUrlError, e.message
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
    raise FetchError, e.message
  end
end
