require_relative "../lib/commands/unified_server_command"

Rails::Command.singleton_class.send(:prepend, Module.new do
  def find_by_namespace(namespace, *)
    case namespace
    when "server"
      Rails::Command::UnifiedServerCommand
    else
      super
    end
  end
end)