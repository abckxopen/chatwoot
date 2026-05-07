# [2026-05-07] Policy Pundit pra CRM Stage. Mesmo padrão do PipelinePolicy:
# - index/show liberados pra qualquer role do account
# - create/update/destroy/reorder só administrator
#
# Reorder é destrutivo do ponto de vista UX (muda ordem visível pra todos),
# então segue gate de admin. Agentes não podem reordenar pipeline alheio.
class Holding::Crm::StagePolicy < ApplicationPolicy
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

  def reorder?
    @account_user.administrator?
  end
end
