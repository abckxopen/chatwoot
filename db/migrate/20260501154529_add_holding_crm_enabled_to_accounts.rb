# [2026-05-01] Boolean dedicado pro fork da holding ativar CRM por conta.
# WHY: chatwoot core usa bitfield int8 signed pra `feature_flags` (concern
# Featurable). Limite real = 63 bits úteis, e o features.yml de upstream
# já tinha 63 entradas. Adicionar `crm_pipeline` no slot 64 estourou no
# save (PG::IntegerOutOfRange / ActiveModel::RangeError). Detectado em
# spec controller do slice 1, fix antes do PR.
#
# Decisão: NÃO mexemos no core (Featurable é compartilhado, mudar tipo
# da coluna `feature_flags` de int8 pra bit varying é mudança invasiva
# que conflita com cherry-pick futuro do upstream — viola fork-policy).
# Em vez disso, isolamos o gate da holding numa coluna boolean dedicada.
# Resolução de conflito em cherry-pick: arquivo é nosso, não tem
# correspondente upstream, simples.
#
# Quebra-se mudar pra: (1) renomear coluna sem migration de transição
# breaks `account.holding_crm_enabled?` em tudo que checa; (2) usar
# JSONB compartilhado quebra type-safety e expõe a flag a sobrescrita
# acidental por endpoints que recebem custom_attributes do client.
class AddHoldingCrmEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :holding_crm_enabled, :boolean, default: false, null: false
  end
end
