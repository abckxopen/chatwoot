# [2026-04-30] Policy Pundit pra CRM Pipeline. Padrão Chatwoot:
# - index/show liberados pra qualquer role do account (admin + agent + roles custom)
# - create/update/destroy só administrator
#
# Decisão "agente vê tudo" intencional: pipeline é metadado de infraestrutura,
# não dado sensível por opp. Esconder pipelines de agente seria UX confuso —
# mas opportunities individuais terão filtro por assignee mais granular.
class Holding::Crm::PipelinePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
