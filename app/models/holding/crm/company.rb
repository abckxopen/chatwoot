# == Schema Information
#
# Table name: crm_companies
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb            not null
#  domain                :string
#  industry              :string
#  name                  :string           not null
#  size                  :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#
# Indexes
#
#  idx_crm_companies_account_domain  (account_id,domain)
#  idx_crm_companies_account_name    (account_id,name) UNIQUE
#  index_crm_companies_on_account_id (account_id)
#

# [2026-04-30] Company entity. Chatwoot upstream tem só `company_name` em
# `Contact#additional_attributes` — esse model trata empresa como first-class.
#
# Relação com Contact: NÃO há FK direto (zero monkey-patch core upstream
# `contacts` table). Service de linkagem (Phase 1) lê/escreve em
# `Contact#additional_attributes['crm_company_id']`. Validação de integridade
# é responsabilidade do service.
class Holding::Crm::Company < ApplicationRecord
  self.table_name = 'crm_companies'

  belongs_to :account
  has_many :opportunities, class_name: 'Holding::Crm::Opportunity',
                           foreign_key: :crm_company_id,
                           inverse_of: :company,
                           dependent: :nullify

  # [2026-04-30] Domínio normalizado lowercase + sem `https://` / `www.`.
  # Soft-validate (regex frouxo) — domain é metadado, não vai bloquear
  # cadastro de empresa por digitação imperfeita.
  DOMAIN_REGEX = /\A(?:(?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)+[A-Za-z]{2,}\z/

  validates :name, presence: true,
                   uniqueness: { scope: :account_id }
  validates :domain, format: { with: DOMAIN_REGEX }, allow_blank: true

  before_validation :normalize_domain

  after_create_commit :dispatch_created_event
  after_update_commit :dispatch_updated_event

  private

  def normalize_domain
    return if domain.blank?

    self.domain = domain.to_s
                        .strip
                        .downcase
                        .sub(%r{\Ahttps?://}, '')
                        .delete_prefix('www.')
                        .split('/').first
  end

  def dispatch_created_event
    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::COMPANY_CREATED,
      Time.zone.now,
      company: self
    )
  end

  def dispatch_updated_event
    Rails.configuration.dispatcher.dispatch(
      ::Holding::Crm::Events::COMPANY_UPDATED,
      Time.zone.now,
      company: self
    )
  end
end
