require 'rails_helper'

RSpec.describe Holding::Crm::Activity do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    # rubocop:disable Layout/LineLength
    it { is_expected.to belong_to(:opportunity).class_name('Holding::Crm::Opportunity').with_foreign_key(:crm_opportunity_id).inverse_of(:activities) }
    # rubocop:enable Layout/LineLength
    it { is_expected.to belong_to(:assignee).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:holding_crm_activity) }

    it { is_expected.to validate_presence_of(:subject) }
  end

  describe 'enum kind' do
    it { is_expected.to define_enum_for(:kind).with_values(call: 0, email: 1, meeting: 2, note: 3, task: 4) }
  end

  describe 'scopes' do
    let!(:open_activity) { create(:holding_crm_activity, due_at: 1.day.from_now) }
    let!(:completed) { create(:holding_crm_activity, :completed) }
    let!(:overdue) { create(:holding_crm_activity, :overdue) }

    it '#open' do
      expect(described_class.open).to contain_exactly(open_activity, overdue)
    end

    it '#completed' do
      expect(described_class.completed).to contain_exactly(completed)
    end

    it '#overdue' do
      expect(described_class.overdue).to contain_exactly(overdue)
    end
  end

  describe '#open? / #overdue?' do
    it 'open? true se completed_at nil' do
      a = build(:holding_crm_activity)
      expect(a.open?).to be true
    end

    it 'open? false se completed_at present' do
      a = build(:holding_crm_activity, :completed)
      expect(a.open?).to be false
    end

    it 'overdue? true se due_at no passado e ainda open' do
      a = build(:holding_crm_activity, :overdue)
      expect(a.overdue?).to be true
    end

    it 'overdue? false se completed' do
      a = build(:holding_crm_activity, :completed, due_at: 2.days.ago)
      expect(a.overdue?).to be false
    end
  end

  describe '#complete!' do
    it 'preenche completed_at com Time.zone.now' do
      a = create(:holding_crm_activity)
      freeze_time = Time.zone.parse('2026-04-30T10:00:00Z')
      a.complete!(at: freeze_time)
      expect(a.reload.completed_at).to be_within(1.second).of(freeze_time)
    end
  end

  describe 'event dispatch' do
    before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

    it 'dispara ACTIVITY_CREATED on create' do
      activity = create(:holding_crm_activity)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::ACTIVITY_CREATED, kind_of(Time), activity: activity
      )
    end

    it 'dispara ACTIVITY_COMPLETED quando completed_at preenchido' do
      activity = create(:holding_crm_activity)
      activity.complete!
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::ACTIVITY_COMPLETED, kind_of(Time), activity: activity
      )
    end

    it 'NÃO dispara ACTIVITY_COMPLETED em update normal sem mudar completed_at' do
      activity = create(:holding_crm_activity)
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original.once
      activity.update!(subject: 'Outro assunto')
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Holding::Crm::Events::ACTIVITY_COMPLETED, anything, anything
      )
    end
  end
end
