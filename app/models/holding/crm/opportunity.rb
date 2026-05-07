# == Schema Information
#
# Table name: crm_opportunities
#
#  id                  :bigint           not null, primary key
#  currency            :string           default("BRL"), not null
#  custom_attributes   :jsonb            not null
#  description         :text
#  discarded_at        :datetime
#  expected_close_date :date
#  lost_at             :datetime
#  lost_reason         :text
#  name                :string           not null
#  probability         :integer          default(0), not null
#  source              :string
#  status              :integer          default("open"), not null
#  value               :decimal(15, 2)
#  won_at              :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  assignee_id         :bigint
#  contact_id          :bigint
#  crm_company_id      :bigint
#  crm_pipeline_id     :bigint           not null
#  crm_stage_id        :bigint           not null
#
# Indexes
#
#  idx_crm_opportunities_account_active        (account_id) WHERE (discarded_at IS NULL)
#  idx_crm_opportunities_account_status        (account_id,status)
#  idx_crm_opportunities_assignee_status       (assignee_id,status)
#  idx_crm_opportunities_close_date            (expected_close_date)
#  idx_crm_opportunities_company               (crm_company_id)
#  idx_crm_opportunities_contact               (contact_id)
#  idx_crm_opportunities_pipeline_stage        (crm_pipeline_id,crm_stage_id)
#  index_crm_opportunities_on_account_id       (account_id)
#  index_crm_opportunities_on_crm_pipeline_id  (crm_pipeline_id)
#  index_crm_opportunities_on_crm_stage_id     (crm_stage_id)
#

# [2026-04-30] Opportunity (Deal). Coração do CRM. Veja brain/crm-pipeline-spec.md.
#
# Tipos de mudança que disparam evento dedicado:
# - create → OPPORTUNITY_CREATED
# - update geral → OPPORTUNITY_UPDATED
# - troca de stage → OPPORTUNITY_STAGE_CHANGED (gatilha integração Matrix)
# - status → won → OPPORTUNITY_WON
# - status → lost → OPPORTUNITY_LOST
#
# A ordem importa: stage_changed dispara antes de won/lost porque alguém
# pode mover pra stage marcada won=true (e queremos que listener Matrix veja
# o evento de stage primeiro pra criar task, e o listener interno marque
# won_at depois).
class Holding::Crm::Opportunity < ApplicationRecord
  self.table_name = 'crm_opportunities'

  # [2026-04-30] Status como Rails enum integer. NÃO trocar índices nem
  # ordem — :open=0, :won=1, :lost=2 vivem em DB. Rails generate métodos
  # `open?`, `won?`, `lost?`, `open!`, scopes `Opportunity.won`, etc.
  enum :status, { open: 0, won: 1, lost: 2 }, default: :open

  # [2026-04-30] Currency limitado a ISO 4217 conhecidas pra MVP. Adicionar
  # nova quebra nada — só validação relaxa. Lista mínima cobre 99% dos
  # casos da holding.
  ALLOWED_CURRENCIES = %w[BRL USD EUR GBP].freeze

  # [2026-05-07] custom_attributes é jsonb open-schema (Phase 4 UI permite
  # campos custom por funil/vila). Permit aberto no controller — cap aqui
  # bloqueia client malicioso jogar 10MB de jsonb no row. 16KB é o mesmo
  # limit usado em Holding::Crm::Company#additional_attributes.
  CUSTOM_ATTRIBUTES_MAX_BYTES = 16 * 1024

  belongs_to :account
  belongs_to :pipeline, class_name: 'Holding::Crm::Pipeline',
                        foreign_key: :crm_pipeline_id,
                        inverse_of: :opportunities
  belongs_to :stage, class_name: 'Holding::Crm::Stage',
                     foreign_key: :crm_stage_id,
                     inverse_of: :opportunities
  belongs_to :company, class_name: 'Holding::Crm::Company',
                       foreign_key: :crm_company_id,
                       inverse_of: :opportunities,
                       optional: true

  # [2026-04-30] Contact é model do core upstream (`Contact`). Optional
  # porque opp pode existir sem contact ainda. on_destroy do Contact:
  # Rails default não cascateia — opp fica órfã com contact_id apontando
  # pra registro removido. Service de cleanup (Phase 5) limpa.
  belongs_to :contact, optional: true

  # [2026-04-30] Assignee = User do core. Optional pra opp não-atribuída.
  belongs_to :assignee, class_name: 'User', optional: true

  has_many :activities, class_name: 'Holding::Crm::Activity',
                        foreign_key: :crm_opportunity_id,
                        inverse_of: :opportunity,
                        dependent: :destroy_async

  validates :name, presence: true
  validates :currency, inclusion: { in: ALLOWED_CURRENCIES }
  validates :probability, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }
  validates :value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :custom_attributes_within_size_limit

  # [2026-04-30] Soft-delete via discarded_at timestamp em vez de gem
  # `discard` — menos dependência. Padrão segue `default_scope-less`:
  # cada query explícita escolhe se quer ativos ou todos.
  scope :active, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  after_create_commit :dispatch_created_event
  after_update_commit :dispatch_updated_event
  after_update_commit :dispatch_stage_changed_event, if: :saved_change_to_crm_stage_id?
  after_update_commit :dispatch_status_lifecycle_event, if: :saved_change_to_status?

  # [2026-04-30] move_to_stage! atualiza stage e auto-aplica won/lost
  # quando a stage destino é marker. Service-layer pra controller chamar
  # em PATCH /move_to_stage. Se mudar comportamento, atualizar
  # CrmListener#crm_opportunity_stage_changed (Phase 2).
  def move_to_stage!(new_stage)
    raise ArgumentError, 'stage required' if new_stage.blank?
    raise ArgumentError, 'stage in different pipeline' if new_stage.crm_pipeline_id != crm_pipeline_id

    attrs = { crm_stage_id: new_stage.id }
    attrs[:status] = :won if new_stage.won? && open?
    attrs[:status] = :lost if new_stage.lost? && open?

    update!(attrs)
  end

  def discard!
    return if discarded?

    update!(discarded_at: Time.zone.now)
  end

  def discarded?
    discarded_at.present?
  end

  private

  def custom_attributes_within_size_limit
    return if custom_attributes.blank?

    serialized_size = custom_attributes.to_json.bytesize
    return if serialized_size <= CUSTOM_ATTRIBUTES_MAX_BYTES

    errors.add(:custom_attributes, :too_large)
  end

  def dispatch_created_event
    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::OPPORTUNITY_CREATED,
      Time.zone.now,
      opportunity: self
    )
  end

  def dispatch_updated_event
    # [2026-04-30] Skip se mudança foi APENAS stage_id ou status — esses
    # têm seus próprios eventos. Senão duplica notificação pro listener.
    return if saved_changes.keys == ['updated_at']
    return if saved_changes.keys.sort == %w[crm_stage_id updated_at]
    return if saved_changes.keys.sort == %w[status updated_at]

    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::OPPORTUNITY_UPDATED,
      Time.zone.now,
      opportunity: self
    )
  end

  def dispatch_stage_changed_event
    old_stage_id, new_stage_id = saved_change_to_crm_stage_id

    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::OPPORTUNITY_STAGE_CHANGED,
      Time.zone.now,
      opportunity: self,
      old_stage_id: old_stage_id,
      new_stage_id: new_stage_id
    )
  end

  def dispatch_status_lifecycle_event
    # [2026-04-30] Auto-set won_at/lost_at quando status muda. NÃO usar
    # before_save — queremos que update_columns no spec não dispare isso
    # (ferramenta de migration usa update_columns).
    case status.to_sym
    when :won
      update_columns(won_at: Time.zone.now) if won_at.blank? # rubocop:disable Rails/SkipsModelValidations
      Rails.configuration.dispatcher.dispatch(
        ::Holding::Crm::Events::OPPORTUNITY_WON,
        Time.zone.now,
        opportunity: self
      )
    when :lost
      update_columns(lost_at: Time.zone.now) if lost_at.blank? # rubocop:disable Rails/SkipsModelValidations
      Rails.configuration.dispatcher.dispatch(
        ::Holding::Crm::Events::OPPORTUNITY_LOST,
        Time.zone.now,
        opportunity: self
      )
    end
  end
end
