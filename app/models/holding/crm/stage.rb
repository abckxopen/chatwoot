# == Schema Information
#
# Table name: crm_stages
#
#  id                    :bigint           not null, primary key
#  color                 :string
#  lost                  :boolean          default(FALSE), not null
#  matrix_task_template  :jsonb            not null
#  name                  :string           not null
#  position              :integer          default(0), not null
#  won                   :boolean          default(FALSE), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  crm_pipeline_id       :bigint           not null
#
# Indexes
#
#  idx_crm_stages_account_pipeline_name  (account_id,crm_pipeline_id,name) UNIQUE
#  idx_crm_stages_pipeline_position      (crm_pipeline_id,position) UNIQUE
#  index_crm_stages_on_account_id        (account_id)
#  index_crm_stages_on_crm_pipeline_id   (crm_pipeline_id)
#

# [2026-04-30] Stage de pipeline. Veja brain/crm-pipeline-spec.md pra
# semântica + brain/fork-policy.md pra justificativa do namespace e prefixo.
class Holding::Crm::Stage < ApplicationRecord
  self.table_name = 'crm_stages'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Holding::Crm::Pipeline',
                        foreign_key: :crm_pipeline_id,
                        inverse_of: :stages

  # [2026-04-30] inverse_of declarado pra rubocop Rails/InverseOf no
  # belongs_to :stage do Opportunity. PG-level on_delete:restrict no FK
  # garante que stage não some com opps vivas — esse dependent é só pra
  # gerar erro Rails em vez de ActiveRecord::InvalidForeignKey.
  has_many :opportunities, class_name: 'Holding::Crm::Opportunity',
                           foreign_key: :crm_stage_id,
                           inverse_of: :stage,
                           dependent: :restrict_with_error

  # [2026-04-30] Regex bate `#RRGGBB` (lowercase ou uppercase) ou NULL.
  # UI exige hex curto/longo padronizado pra picker; relaxar exige
  # parser de cores no frontend.
  HEX_COLOR_REGEX = /\A#(?:[0-9a-fA-F]{6})\z/

  validates :name, presence: true,
                   uniqueness: { scope: %i[account_id crm_pipeline_id] }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :color, format: { with: HEX_COLOR_REGEX }, allow_blank: true
  validates :won, inclusion: { in: [true, false] }
  validates :lost, inclusion: { in: [true, false] }

  # [2026-04-30] Stage não pode ser ao mesmo tempo won E lost — semântica
  # mutuamente exclusiva. Ambos false = stage normal (em aberto).
  validate :won_xor_lost

  scope :ordered, -> { order(position: :asc, id: :asc) }

  after_create_commit :dispatch_created_event
  after_update_commit :dispatch_updated_event

  # [2026-05-07] Reorder em batch preservando UNIQUE (crm_pipeline_id, position).
  # PG checa unique index por-row (não diferível p/ unique INDEX, só p/ unique
  # CONSTRAINT), então 1 pass direto pra 0..N-1 colide com rows ainda na ordem
  # antiga. Estratégia 2-pass:
  # 1. Move tudo pra range temporário (offset > N) — sem colisão.
  # 2. Assigna 0..N-1 final.
  #
  # Lock no pipeline row pra serializar reorders concorrentes na mesma pipeline
  # (sem ele, dois reorders simultâneos pegam o mesmo safe_offset e
  # PG::UniqueViolation aborta um). Diferentes pipelines não contendem.
  #
  # Validação: ordered_ids precisa ser EXATAMENTE o conjunto das stages do
  # pipeline. Reorder parcial criaria gap de position; ids estranhos seriam
  # vazamento cross-pipeline.
  def self.update_positions_for_pipeline!(pipeline:, ordered_ids:)
    transaction do
      pipeline_locked = Holding::Crm::Pipeline.lock.find(pipeline.id)
      pipeline_stage_ids = pipeline_locked.stages.pluck(:id)

      if ordered_ids.sort != pipeline_stage_ids.sort
        raise ArgumentError, 'ordered_ids must include exactly the pipeline stages'
      end

      safe_offset = pipeline_stage_ids.size + 1000
      # Pass 1: range temporário (positions > qualquer valor válido futuro).
      # update_all bypassa won_xor_lost / position validations, mas só mexemos
      # em :position, então é seguro.
      ordered_ids.each_with_index do |id, idx|
        pipeline_locked.stages.where(id: id).update_all(position: safe_offset + idx) # rubocop:disable Rails/SkipsModelValidations
      end
      # Pass 2: posições finais.
      ordered_ids.each_with_index do |id, idx|
        pipeline_locked.stages.where(id: id).update_all(position: idx) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end

  private

  def won_xor_lost
    return unless won? && lost?

    errors.add(:base, :won_and_lost_cannot_coexist)
  end

  def dispatch_created_event
    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::STAGE_CREATED,
      Time.zone.now,
      stage: self
    )
  end

  def dispatch_updated_event
    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::STAGE_UPDATED,
      Time.zone.now,
      stage: self
    )
  end
end
