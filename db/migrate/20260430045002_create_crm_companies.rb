# [2026-04-30] Migration #3 da Phase 0 — `crm_companies`.
#
# Companies (empresas) — model novo. Chatwoot upstream tem só `company_name`
# em campo solto no Contact (`additional_attributes['company_name']`), sem
# entidade própria. Este model trata empresa como first-class: tem nome,
# domínio, indústria, e relações com Contacts e Opportunities.
#
# Relação Company ↔ Contact: NÃO mexemos em `contacts` table (zero monkey
# patch core). Contact aponta pra company via `additional_attributes['crm_company_id']`
# JSONB existente upstream — soft FK gerenciada por service. Trade-off:
# perdemos integridade referencial em DB, mas ganhamos zero conflito de
# rebase. Validação no service em Phase 1.
class CreateCrmCompanies < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_companies do |t|
      t.references :account, null: false, foreign_key: true, index: true

      t.string :name, null: false
      # [2026-04-30] Domínio (ex: "abckx.com.br") — usado pra auto-vincular
      # contacts por domínio do email. Lowercase normalizado no model.
      t.string :domain
      t.string :industry
      # [2026-04-30] Tamanho como string ("1-10", "11-50", "51-200", etc.) —
      # mantém flexível sem precisar enum. Validação opcional via constants
      # no model.
      t.string :size

      # [2026-04-30] JSONB pra atributos extras (linkedin_url, billing_address,
      # tax_id, etc.) sem precisar migration cada campo novo.
      t.jsonb :additional_attributes, null: false, default: {}

      t.timestamps
    end

    # [2026-04-30] Não-unique em domain porque pode ter 2 empresas no mesmo
    # domínio (subsidiárias) — mas index pra query rápida. Unique fica em
    # (account_id, name) — mesma lógica do pipeline.
    add_index :crm_companies, [:account_id, :name], unique: true,
                                                    name: 'idx_crm_companies_account_name'
    add_index :crm_companies, [:account_id, :domain],
              name: 'idx_crm_companies_account_domain'
  end
end
