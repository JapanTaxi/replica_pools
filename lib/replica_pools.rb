require 'active_record'
require 'replica_pools/config'
require 'replica_pools/pool'
require 'replica_pools/pools'
require 'replica_pools/active_record_extensions'
require 'replica_pools/hijack'
require 'replica_pools/query_cache'
require 'replica_pools/connection_proxy'

require 'replica_pools/engine' if defined? Rails
ActiveRecord::Base.send :include, ReplicaPools::ActiveRecordExtensions

module ReplicaPools
  class << self

    def config
      @config ||= ReplicaPools::Config.new
    end

    def setup!
      ConnectionProxy.generate_safe_delegations

      log :info, "Proxy loaded with: #{pools.keys.join(', ')}"
    end

    def proxies
      Thread.current[:replica_pools_proxies] ||= {}
    end

    def proxy(klass, db_name)
      raise "Connection pools for #{db_name} not found" if pools[db_name].empty?
      proxies[db_name] ||= ReplicaPools::ConnectionProxy.new(klass, pools[db_name])
    end

    def pools
      Thread.current[:replica_pools] ||= ReplicaPools::Pools.new
    end

    def log(level, message)
      logger.send(level, "[ReplicaPools] #{message}")
    end

    def logger
      ActiveRecord::Base.logger
    end
  end
end
