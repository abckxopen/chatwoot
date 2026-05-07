# [2026-05-07] Policy Pundit pra CRM Company. Mesmo gate dos outros CRM:
# - index/show liberados pra qualquer role (admin + agent)
# - create/update/destroy só administrator
#
# Companies são metadata compartilhada do funil — qualquer agente que cuida
# de opportunities precisa enxergar empresa. Restringir cadastro/edição a
# admin garante consistência (evita o ChatGPT do agent criar Company duplicada
# por digitação imperfeita).
class Holding::Crm::CompanyPolicy < ApplicationPolicy
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
