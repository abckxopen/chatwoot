# == Schema Information
#
# Table name: crm_pipelines
#
#  id               :bigint           not null, primary key
#  default_pipeline :boolean          default(FALSE), not null
#  description      :text
#  name             :string           not null
#  position         :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_crm_pipelines_on_account_id           (account_id)
#  index_crm_pipelines_on_account_id_and_name  (account_id,name) UNIQUE
#

# [2026-04-30] Model do CRM da holding — Pipeline (funil de vendas).
#
# Namespace `Holding::Crm::*` (não só `Crm::*`) porque o upstream Chatwoot
# JÁ TEM `Crm::*` ocupado por integração LeadSquared (`app/services/crm/`).
# Reusar `Crm::` colidiria com classes existentes. Trocar namespace quebra
# autoload e factory references.
#
# Tabela: `crm_pipelines` (sem prefixo `holding_` na tabela). Padrão Rails
# default seria `holding_crm_pipelines` — sobrescrevemos com `self.table_name`
# pra manter o prefixo de tabela `crm_*` consistente com fork-policy.md
# (anti-conflito com migrations futuras do upstream).
class Holding::Crm::Pipeline < ApplicationRecord
  self.table_name = 'crm_pipelines'

  belongs_to :account
  has_many :stages, class_name: 'Holding::Crm::Stage',
                    foreign_key: :crm_pipeline_id,
                    inverse_of: :pipeline,
                    dependent: :destroy_async
  has_many :opportunities, class_name: 'Holding::Crm::Opportunity',
                           foreign_key: :crm_pipeline_id,
                           inverse_of: :pipeline,
                           dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :default_pipeline, inclusion: { in: [true, false] }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # [2026-04-30] Apenas 1 pipeline default por account. Validação a nível de
  # model (não constraint Postgres parcial) porque erro precisa virar
  # ActiveRecord::RecordInvalid amigável na API. Trocar pra constraint exige
  # rescue específico no controller.
  validate :only_one_default_per_account

  scope :defaults_first, -> { order(default_pipeline: :desc, position: :asc, id: :asc) }

  after_create_commit :dispatch_created_event
  after_update_commit :dispatch_updated_event
  after_destroy_commit :dispatch_deleted_event

  private

  # [2026-04-30] Query direta em vez de `account.crm_pipelines` porque
  # `Account` é model upstream — não estamos adicionando has_many lá pra
  # respeitar fork-policy "zero monkey-patch core". Trade-off: temos que
  # filtrar por account_id manualmente em queries CRM. A consistência é
  # garantida por validação `account_id presence: true` herdada de
  # belongs_to :account.
  def only_one_default_per_account
    return unless default_pipeline?
    return if account_id.blank?

    scope = self.class.where(account_id: account_id, default_pipeline: true)
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:default_pipeline, :only_one_default_per_account)
  end

  def dispatch_created_event
    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::PIPELINE_CREATED,
      Time.zone.now,
      pipeline: self
    )
  end

  def dispatch_updated_event
    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::PIPELINE_UPDATED,
      Time.zone.now,
      pipeline: self
    )
  end

  def dispatch_deleted_event
    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::PIPELINE_DELETED,
      Time.zone.now,
      pipeline_id: id,
      account_id: account_id
    )
  end
end
