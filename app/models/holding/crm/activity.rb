# == Schema Information
#
# Table name: crm_activities
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  description        :text
#  due_at             :datetime
#  kind               :integer          default("task"), not null
#  matrix_task_id     :string
#  subject            :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  assignee_id        :bigint
#  crm_opportunity_id :bigint           not null
#
# Indexes
#
#  idx_crm_activities_assignee_completed     (assignee_id,completed_at)
#  idx_crm_activities_open_due               (account_id,due_at) WHERE (completed_at IS NULL)
#  idx_crm_activities_opp_due                (crm_opportunity_id,due_at)
#  index_crm_activities_on_account_id        (account_id)
#  index_crm_activities_on_crm_opportunity_id (crm_opportunity_id)
#

# [2026-04-30] Activity (atividade/prazo) por opportunity. Permite
# múltiplas tasks por opp ao longo do funil — Founder pediu o "basico
# agora, mas ja pensando que podemos colocar mais tasks ali por fase"
# (msg 270).
module Holding
  module Crm
    class Activity < ApplicationRecord
      self.table_name = 'crm_activities'

      # [2026-04-30] Kind enum integer. NÃO trocar índices: 0=call, 1=email,
      # 2=meeting, 3=note, 4=task. Adicionar tipo novo é OK (next int).
      enum :kind, { call: 0, email: 1, meeting: 2, note: 3, task: 4 }, default: :task

      belongs_to :account
      belongs_to :opportunity, class_name: 'Holding::Crm::Opportunity',
                               foreign_key: :crm_opportunity_id,
                               inverse_of: :activities
      # [2026-04-30] Assignee = User core. Optional pra activity geral.
      belongs_to :assignee, class_name: 'User', optional: true

      validates :subject, presence: true

      scope :open, -> { where(completed_at: nil) }
      scope :completed, -> { where.not(completed_at: nil) }
      scope :overdue, -> { open.where('due_at < ?', Time.zone.now) }
      scope :due_within, ->(window) { open.where(due_at: Time.zone.now..(Time.zone.now + window)) }

      after_create_commit :dispatch_created_event
      after_update_commit :dispatch_completed_event, if: :just_completed?

      def open?
        completed_at.blank?
      end

      def overdue?
        open? && due_at.present? && due_at.past?
      end

      # [2026-04-30] complete! sem args usa now. Rails update marca
      # `saved_change_to_completed_at` que aciona dispatch_completed_event.
      def complete!(at: Time.zone.now)
        update!(completed_at: at)
      end

      private

      def just_completed?
        saved_change_to_completed_at? && completed_at.present?
      end

      def dispatch_created_event
        Rails.configuration.dispatcher.dispatch(
          ::Holding::Crm::Events::ACTIVITY_CREATED,
          Time.zone.now,
          activity: self
        )
      end

      def dispatch_completed_event
        Rails.configuration.dispatcher.dispatch(
          ::Holding::Crm::Events::ACTIVITY_COMPLETED,
          Time.zone.now,
          activity: self
        )
      end
    end
  end
end
