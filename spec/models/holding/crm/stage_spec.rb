require 'rails_helper'

RSpec.describe Holding::Crm::Stage do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:pipeline).class_name('Holding::Crm::Pipeline').with_foreign_key(:crm_pipeline_id).inverse_of(:stages) }
  end

  describe 'validations' do
    subject { build(:holding_crm_stage) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(%i[account_id crm_pipeline_id]) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to allow_value('#3B82F6', '#ff00aa').for(:color) }
    it { is_expected.not_to allow_value('blue', '#ZZZ', '#1234567').for(:color) }

    it 'allow blank color (UI fallback)' do
      stage = build(:holding_crm_stage, color: nil)
      expect(stage).to be_valid
    end

    describe '#won_xor_lost' do
      it 'permite stage com won=true e lost=false' do
        expect(build(:holding_crm_stage, :won)).to be_valid
      end

      it 'permite stage com lost=true e won=false' do
        expect(build(:holding_crm_stage, :lost)).to be_valid
      end

      it 'rejeita stage com won=true E lost=true' do
        stage = build(:holding_crm_stage, won: true, lost: true)
        expect(stage).not_to be_valid
        expect(stage.errors).to be_of_kind(:base, :won_and_lost_cannot_coexist)
      end
    end
  end

  describe 'event dispatch' do
    before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

    it 'dispara crm.stage.created on create' do
      stage = create(:holding_crm_stage)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::STAGE_CREATED, kind_of(Time), stage: stage
      )
    end

    it 'dispara crm.stage.updated on update' do
      stage = create(:holding_crm_stage)
      stage.update!(name: 'Renomeado')
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::STAGE_UPDATED, kind_of(Time), stage: stage
      ).at_least(:once)
    end
  end
end
