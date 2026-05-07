require 'rails_helper'

RSpec.describe Holding::Crm::Opportunity do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:pipeline).class_name('Holding::Crm::Pipeline').with_foreign_key(:crm_pipeline_id).inverse_of(:opportunities) }
    it { is_expected.to belong_to(:stage).class_name('Holding::Crm::Stage').with_foreign_key(:crm_stage_id) }
    it { is_expected.to belong_to(:company).class_name('Holding::Crm::Company').optional }
    it { is_expected.to belong_to(:contact).optional }
    it { is_expected.to belong_to(:assignee).class_name('User').optional }
    it { is_expected.to have_many(:activities).class_name('Holding::Crm::Activity').with_foreign_key(:crm_opportunity_id) }
  end

  describe 'validations' do
    subject { build(:holding_crm_opportunity) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:currency).in_array(described_class::ALLOWED_CURRENCIES) }
    it { is_expected.to validate_numericality_of(:probability).only_integer.is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
    it { is_expected.to validate_numericality_of(:value).is_greater_than_or_equal_to(0).allow_nil }

    describe 'custom_attributes size cap' do
      it 'aceita custom_attributes pequeno' do
        opp = build(:holding_crm_opportunity, custom_attributes: { region: 'BR-RS', source_detail: 'cold-email' })
        expect(opp).to be_valid
      end

      it 'rejeita custom_attributes > 16KB serializado' do
        big_value = 'a' * 20_000
        opp = build(:holding_crm_opportunity, custom_attributes: { bloat: big_value })
        expect(opp).not_to be_valid
        expect(opp.errors).to be_of_kind(:custom_attributes, :too_large)
      end
    end
  end

  describe 'enum status' do
    it { is_expected.to define_enum_for(:status).with_values(open: 0, won: 1, lost: 2) }
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:pipeline) { create(:holding_crm_pipeline, account: account) }
    let!(:active) { create(:holding_crm_opportunity, account: account, pipeline: pipeline) }
    let!(:discarded) { create(:holding_crm_opportunity, :discarded, account: account, pipeline: pipeline) }

    # [2026-05-07] Comparar por id em vez de record. Pattern do mesmo bug
    # de pipeline_spec — AR `==` retornando false em records de mesma id/classe
    # quando rodando no mesmo partition CI com novos specs. Root cause não
    # diagnosticado, suspeita autoload pollution. `.pluck(:id)` é semanticamente
    # equivalente pro intent do scope teste.
    it '#active retorna apenas non-discarded' do
      expect(described_class.active.pluck(:id)).to contain_exactly(active.id)
    end

    it '#discarded retorna apenas discarded' do
      expect(described_class.discarded.pluck(:id)).to contain_exactly(discarded.id)
    end
  end

  describe '#move_to_stage!' do
    let(:account) { create(:account) }
    let(:pipeline) { create(:holding_crm_pipeline, account: account) }
    let(:stage_a) { create(:holding_crm_stage, pipeline: pipeline, account: account, position: 0) }
    let(:stage_b) { create(:holding_crm_stage, pipeline: pipeline, account: account, position: 1) }
    let(:won_stage) { create(:holding_crm_stage, :won, pipeline: pipeline, account: account, position: 99) }
    let(:lost_stage) { create(:holding_crm_stage, :lost, pipeline: pipeline, account: account, position: 100) }
    let(:opp) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage_a) }

    before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

    it 'troca stage_id e mantém status open quando stage destino não é won/lost' do
      opp.move_to_stage!(stage_b)
      expect(opp.reload.crm_stage_id).to eq(stage_b.id)
      expect(opp.status).to eq('open')
    end

    it 'auto-aplica status=won quando stage destino é won' do
      opp.move_to_stage!(won_stage)
      expect(opp.reload).to have_attributes(crm_stage_id: won_stage.id, status: 'won')
      expect(opp.won_at).to be_present
    end

    it 'auto-aplica status=lost quando stage destino é lost' do
      opp.move_to_stage!(lost_stage)
      expect(opp.reload).to have_attributes(crm_stage_id: lost_stage.id, status: 'lost')
      expect(opp.lost_at).to be_present
    end

    it 'rejeita stage de pipeline diferente' do
      other_pipeline = create(:holding_crm_pipeline, account: account)
      foreign_stage = create(:holding_crm_stage, pipeline: other_pipeline, account: account)
      expect { opp.move_to_stage!(foreign_stage) }.to raise_error(ArgumentError, /different pipeline/)
    end

    it 'dispara OPPORTUNITY_STAGE_CHANGED' do
      opp.move_to_stage!(stage_b)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::OPPORTUNITY_STAGE_CHANGED,
        kind_of(Time),
        opportunity: opp,
        old_stage_id: stage_a.id,
        new_stage_id: stage_b.id
      )
    end
  end

  describe '#discard!' do
    it 'preenche discarded_at e some do scope active' do
      opp = create(:holding_crm_opportunity)
      opp.discard!
      expect(opp.discarded?).to be true
      expect(opp.discarded_at).to be_present
    end

    it 'no-op se já discarded' do
      opp = create(:holding_crm_opportunity, :discarded)
      original_at = opp.discarded_at
      opp.discard!
      expect(opp.reload.discarded_at).to eq(original_at)
    end
  end

  describe 'event dispatch' do
    before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

    it 'dispara OPPORTUNITY_CREATED on create' do
      opp = create(:holding_crm_opportunity)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::OPPORTUNITY_CREATED, kind_of(Time), opportunity: opp
      )
    end

    it 'dispara OPPORTUNITY_UPDATED on update geral (não stage, não status)' do
      opp = create(:holding_crm_opportunity)
      opp.update!(name: 'Renomeada', value: 999)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::OPPORTUNITY_UPDATED, kind_of(Time), opportunity: opp
      ).at_least(:once)
    end

    it 'dispara OPPORTUNITY_WON quando status muda pra won' do
      opp = create(:holding_crm_opportunity)
      opp.update!(status: :won)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::OPPORTUNITY_WON, kind_of(Time), opportunity: opp
      )
      expect(opp.reload.won_at).to be_present
    end

    it 'dispara OPPORTUNITY_LOST quando status muda pra lost' do
      opp = create(:holding_crm_opportunity)
      opp.update!(status: :lost, lost_reason: 'sem orçamento')
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::OPPORTUNITY_LOST, kind_of(Time), opportunity: opp
      )
      expect(opp.reload.lost_at).to be_present
    end
  end

  describe 'tenancy isolation' do
    it 'queries com account_id não retornam opps de outras accounts' do
      acc_a = create(:account)
      acc_b = create(:account)
      opp_a = create(:holding_crm_opportunity, pipeline_account: acc_a)
      _opp_b = create(:holding_crm_opportunity, pipeline_account: acc_b)

      # [2026-05-07] .pluck(:id) — mesmo workaround do pipeline_spec.
      expect(described_class.where(account_id: acc_a.id).pluck(:id)).to contain_exactly(opp_a.id)
    end
  end
end
