# [2026-05-07 abckxopen-fork] HTTP client pra Matrix Mission Control API.
# Usado por Holding::CrmNotifyMatrixJob na integração one-way CRM → Matrix.
#
# Por que HTTParty (e não Faraday/Net::HTTP direto): chatwoot já usa
# HTTParty no resto da codebase (WebsiteBrandingService, Slack/Instagram
# integrations). Mantém um único cliente HTTP no fork.
#
# Por que classes de erro separadas (ClientError 4xx vs ServerError 5xx):
# Sidekiq retry semântica precisa distinguir. 4xx é fatal (config errada,
# token revogado, board inexistente — retry não resolve). 5xx + transport
# é transitório (Matrix indisponível, rede flap — retry com backoff).
#
# Endpoint contract: POST {base_url}/boards/{board_id}/tasks
# Schema TaskCreate (matrix/backend/app/schemas/tasks.py): title (req),
# description, status, priority, due_at, type, requires_review, etc.
# Auth: Bearer {MATRIX_API_TOKEN} + X-Agent-Name header (best practice
# match com matrix mc_curl helper, identifica origem nos logs Matrix).
class Holding::Crm::MatrixApiClient
  class ClientError < StandardError; end
  class ServerError < StandardError; end

  TIMEOUT_SECONDS = 10
  DEFAULT_BASE_URL = 'https://matrix.abckx.com.br'.freeze
  DEFAULT_AGENT_NAME = 'chatwoot-crm'.freeze

  def initialize(base_url: nil, token: nil, agent_name: nil)
    @base_url = (base_url || ENV.fetch('MATRIX_API_URL', DEFAULT_BASE_URL)).chomp('/')
    @token = token || ENV['MATRIX_API_TOKEN']
    @agent_name = agent_name || ENV.fetch('MATRIX_AGENT_NAME', DEFAULT_AGENT_NAME)
  end

  # Returns parsed response body (Hash) on 2xx; raises on errors.
  def create_task(board_id:, payload:)
    raise ArgumentError, 'MATRIX_API_TOKEN not set' if @token.blank?
    raise ArgumentError, 'board_id required' if board_id.blank?

    url = "#{@base_url}/boards/#{board_id}/tasks"
    response = HTTParty.post(url, headers: headers, body: payload.to_json, timeout: TIMEOUT_SECONDS)
    handle(response)
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise ServerError, "transport error: #{e.class}: #{e.message}"
  end

  private

  def headers
    {
      'Authorization' => "Bearer #{@token}",
      'X-Agent-Name' => @agent_name,
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def handle(response)
    code = response.code
    return parse_body(response) if code.between?(200, 299)
    raise ClientError, "matrix #{code}: #{truncate(response.body)}" if code.between?(400, 499)

    raise ServerError, "matrix #{code}: #{truncate(response.body)}"
  end

  def parse_body(response)
    JSON.parse(response.body || '{}')
  rescue JSON::ParserError
    raise ServerError, "matrix returned non-JSON body (code=#{response.code})"
  end

  def truncate(body, limit: 500)
    return '' if body.blank?

    body.to_s[0, limit]
  end
end
