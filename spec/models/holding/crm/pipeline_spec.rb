require 'rails_helper'

RSpec.describe Holding::Crm::Pipeline do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    subject { build(:holding_crm_pipeline) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:account_id) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }

    describe 'only_one_default_per_account' do
      let(:account) { create(:account) }

      # [2026-04-30] Validação de model: 1 default por account. Testar com
      # 2 accounts é importante porque comprova que tenancy isolation
      # também se aplica à regra (account A pode ter default mesmo se
      # account B já tem outro default).
      it 'permite 1 pipeline default por account' do
        create(:holding_crm_pipeline, :default, account: account)
        second = build(:holding_crm_pipeline, :default, account: account)

        expect(second).not_to be_valid
        expect(second.errors).to be_of_kind(:default_pipeline, :only_one_default_per_account)
      end

      it 'permite default em accounts diferentes (tenancy isolation)' do
        other_account = create(:account)
        create(:holding_crm_pipeline, :default, account: account)
        second = build(:holding_crm_pipeline, :default, account: other_account)

        expect(second).to be_valid
      end

      it 'permite update mantendo o mesmo default' do
        pipeline = create(:holding_crm_pipeline, :default, account: account)
        pipeline.name = 'Renomeado'

        expect(pipeline).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }

    it '#defaults_first ordena com default antes, depois por position' do
      _other_account_pipeline = create(:holding_crm_pipeline, account: create(:account))
      regular = create(:holding_crm_pipeline, account: account, position: 5)
      default_pipe = create(:holding_crm_pipeline, :default, account: account, position: 10)
      first_position = create(:holding_crm_pipeline, account: account, position: 1)

      result = described_class.where(account: account).defaults_first

      expect(result).to eq([default_pipe, first_position, regular])
    end
  end

  describe 'event dispatch' do
    let(:account) { create(:account) }

    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'dispara crm.pipeline.created on create' do
      pipeline = create(:holding_crm_pipeline, account: account)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::PIPELINE_CREATED,
        kind_of(Time),
        pipeline: pipeline
      )
    end

    it 'dispara crm.pipeline.updated on update' do
      pipeline = create(:holding_crm_pipeline, account: account)
      pipeline.update!(name: 'Renomeado')

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::PIPELINE_UPDATED,
        kind_of(Time),
        pipeline: pipeline
      ).at_least(:once)
    end

    it 'dispara crm.pipeline.deleted on destroy' do
      pipeline = create(:holding_crm_pipeline, account: account)
      pipeline_id = pipeline.id
      account_id = pipeline.account_id

      pipeline.destroy!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::PIPELINE_DELETED,
        kind_of(Time),
        pipeline_id: pipeline_id,
        account_id: account_id
      )
    end
  end

  describe 'tenancy isolation' do
    # [2026-04-30] Garantia explícita: query sem account_id não deve cruzar
    # contas. Multi-tenancy do Chatwoot é comportamental — esse teste serve
    # de canário pra quando qualquer dev (ou eu) esquecer de scope by account.
    it 'queries com account_id não retornam pipelines de outras accounts' do
      account_a = create(:account)
      account_b = create(:account)
      pipe_a = create(:holding_crm_pipeline, account: account_a)
      _pipe_b = create(:holding_crm_pipeline, account: account_b)

      result = described_class.where(account_id: account_a.id)

      expect(result).to contain_exactly(pipe_a)
    end
  end
end
