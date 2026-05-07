require 'rails_helper'

# [2026-05-07] Specs do client HTTP Matrix. Foco em mapeamento status →
# classes de erro (ClientError 4xx fatal, ServerError 5xx + transport
# transitório), pois é isso que define a semântica de retry do job
# acima — se mapear errado, dead set explode em prod.
RSpec.describe Holding::Crm::MatrixApiClient do
  let(:base_url) { 'https://matrix.test' }
  let(:token) { 'tkn-test-123' }
  let(:client) { described_class.new(base_url: base_url, token: token, agent_name: 'chatwoot-crm-test') }
  let(:board_id) { 'a46a66a2-e393-405c-94e1-0d73cda3a11f' }
  let(:url) { "#{base_url}/boards/#{board_id}/tasks" }
  let(:payload) { { title: 'Acompanhar X', priority: 'medium' } }

  describe '#create_task' do
    context 'when matrix returns 200' do
      before do
        stub_request(:post, url)
          .with(headers: { 'Authorization' => "Bearer #{token}", 'X-Agent-Name' => 'chatwoot-crm-test' })
          .to_return(status: 200, body: { id: 'task-uuid-1', title: 'Acompanhar X' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns parsed body hash' do
        expect(client.create_task(board_id: board_id, payload: payload)).to eq(
          'id' => 'task-uuid-1', 'title' => 'Acompanhar X'
        )
      end
    end

    context 'when matrix returns 4xx' do
      before do
        stub_request(:post, url).to_return(status: 422, body: { error: 'invalid_board' }.to_json)
      end

      it 'raises ClientError (fatal — Sidekiq discards)' do
        expect { client.create_task(board_id: board_id, payload: payload) }
          .to raise_error(described_class::ClientError, /matrix 422/)
      end
    end

    context 'when matrix returns 5xx' do
      before do
        stub_request(:post, url).to_return(status: 503, body: 'gateway timeout')
      end

      it 'raises ServerError (transitório — Sidekiq retries)' do
        expect { client.create_task(board_id: board_id, payload: payload) }
          .to raise_error(described_class::ServerError, /matrix 503/)
      end
    end

    context 'when transport fails (network down)' do
      before do
        stub_request(:post, url).to_raise(Errno::ECONNREFUSED.new('refused'))
      end

      it 'raises ServerError (transport mapped to retryable)' do
        expect { client.create_task(board_id: board_id, payload: payload) }
          .to raise_error(described_class::ServerError, /transport error.*ECONNREFUSED/)
      end
    end

    context 'when timeout fires' do
      before do
        stub_request(:post, url).to_raise(Net::ReadTimeout.new)
      end

      it 'raises ServerError' do
        expect { client.create_task(board_id: board_id, payload: payload) }
          .to raise_error(described_class::ServerError, /transport error.*ReadTimeout/)
      end
    end

    context 'when matrix returns non-JSON 2xx' do
      before do
        stub_request(:post, url).to_return(status: 200, body: '<html>oops</html>')
      end

      it 'raises ServerError (server is misbehaving — retry maybe helps)' do
        expect { client.create_task(board_id: board_id, payload: payload) }
          .to raise_error(described_class::ServerError, /non-JSON/)
      end
    end

    context 'when token missing' do
      let(:client) { described_class.new(base_url: base_url, token: nil) }

      it 'raises ConfigError before HTTP call' do
        expect { client.create_task(board_id: board_id, payload: payload) }
          .to raise_error(described_class::ConfigError, /MATRIX_API_TOKEN/)
      end
    end

    context 'when board_id missing' do
      it 'raises ArgumentError' do
        expect { client.create_task(board_id: '', payload: payload) }
          .to raise_error(ArgumentError, /board_id/)
      end
    end
  end
end
