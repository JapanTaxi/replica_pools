module ReplicaPools
  class Config
    # The current environment. Normally set to Rails.env, but
    # will default to 'development' outside of Rails apps.
    attr_accessor :environment

    # When true, all queries will go to leader unless wrapped in with_pool{}.
    # When false, all safe queries will go to the current replica unless wrapped in with_leader{}.
    # Defaults to false.
    attr_accessor :defaults_to_leader

    # The list of methods considered safe to send to a readonly connection.
    # Defaults are based on Rails version.
    attr_accessor :safe_methods

    # When false, replica pools is completely disabled.
    # Defaults to true
    attr_accessor :enabled

    def initialize
      @environment        = 'development'
      @defaults_to_leader = false
      @safe_methods       = []
      @enabled            = true
    end

    def enabled?
      @enabled
    end
  end
end
