# [2026-05-07 abckxopen-fork] Registra Holding::CrmListener no AsyncDispatcher
# via prepend de Module anônimo. Padrão Wisper do chatwoot:
# AsyncDispatcher#listeners retorna um Array de listener instances pré-
# inicializados; load_listeners faz subscribe de cada.
#
# Por que prepend (não monkey-patch direto): mantém upstream `listeners`
# intocado, fácil de cherry-pick. Padrão match com `prepend_mod_with` que
# o próprio AsyncDispatcher usa pra extensões enterprise.
Rails.application.config.to_prepare do
  AsyncDispatcher.prepend(Module.new do
    def listeners
      super + [Holding::CrmListener.instance]
    end
  end)
end
