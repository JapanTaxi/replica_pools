require 'active_record/connection_adapters/abstract/query_cache'
require 'set'

module SlavePools
  class ConnectionProxy
    include ActiveRecord::ConnectionAdapters::QueryCache
    include QueryCacheCompat

    attr_accessor :master
    attr_accessor :master_depth, :current, :current_pool, :slave_pools

    class << self
      def generate_safe_delegations
        SlavePools.config.safe_methods.each do |method|
          generate_safe_delegation(method) unless instance_methods.include?(method)
        end
      end

      protected

      def generate_safe_delegation(method)
        class_eval %Q{
          def #{method}(*args, &block)
            send_to_current(:#{method}, *args, &block)
          end
        }, __FILE__, __LINE__
      end
    end

    def initialize(master, slave_pools)
      @master       = master
      @slave_pools  = slave_pools
      @master_depth = 0
      @reconnect    = false
      @current_pool = default_pool

      if SlavePools.config.defaults_to_master
        @current = @master
        @master_depth = 1
      else
        @current = current_slave
      end

      # this ivar is for ConnectionAdapter compatibility
      # some gems (e.g. newrelic_rpm) will actually use
      # instance_variable_get(:@config) to find it.
      @config = current.connection_config
    end

    def with_pool(pool_name = 'default')
      last_conn, last_pool = self.current, self.current_pool
      self.current_pool = slave_pools[pool_name.to_sym] || default_pool
      self.current = current_slave unless within_master_block?
      yield
    ensure
      self.current_pool = last_pool
      self.current      = last_conn
    end

    def with_master
      last_conn = self.current
      self.current = master
      self.master_depth += 1
      yield
    ensure
      self.master_depth = [master_depth - 1, 0].max # ensure that master depth never gets below 0
      self.current = last_conn
    end

    def transaction(*args, &block)
      with_master { master.transaction(*args, &block) }
    end

    # Switches to the next slave database for read operations.
    # Fails over to the master database if all slaves are unavailable.
    def next_slave!
      return if within_master_block? # don't if in with_master block
      self.current = current_pool.next
    rescue
      self.current = master
    end

    def current_slave
      current_pool.current
    end

    protected

    def default_pool
      slave_pools[:default] || slave_pools.values.first #if there is no default specified, use the first pool found
    end

    # Proxies any unknown methods to master.
    # Safe methods have been generated during `setup!`.
    # Creates a method to speed up subsequent calls.
    def method_missing(method, *args, &block)
      generate_unsafe_delegation(method)
      send(method, *args, &block)
    end

    def within_master_block?
      master_depth > 0
    end

    def generate_unsafe_delegation(method)
      self.instance_eval %Q{
        def #{method}(*args, &block)
          send_to_master(:#{method}, *args, &block)
        end
      }, __FILE__, __LINE__
    end

    def send_to_master(method, *args, &block)
      reconnect_master! if @reconnect
      master.retrieve_connection.send(method, *args, &block)
    rescue => e
      log_errors(e, 'send_to_master', method)
      raise_master_error(e)
    end

    def send_to_current(method, *args, &block)
      reconnect_master! if @reconnect && master?
      # logger.debug "[SlavePools] Using #{current.name}"
      current.retrieve_connection.send(method, *args, &block)
    rescue Mysql2::Error, ActiveRecord::StatementInvalid => e
      log_errors(e, 'send_to_current', method)
      raise_master_error(e) if master?
      logger.warn "[SlavePools] Error reading from slave database"
      logger.error %(#{e.message}\n#{e.backtrace.join("\n")})
      if e.message.match(/Timeout waiting for a response from the last query/)
        # Verify that the connection is active & re-raise
        logger.error "[SlavePools] Slave Query Timeout - do not send to master"
        current.retrieve_connection.verify!
        raise e
      else
        logger.error "[SlavePools] Slave Query Error - sending to master"
        send_to_master(method, *args, &block) # if cant connect, send the query to master
      end
    end

    def reconnect_master!
      master.retrieve_connection.reconnect!
      @reconnect = false
    end

    def raise_master_error(error)
      logger.fatal "[SlavePools] Error accessing master database. Scheduling reconnect"
      @reconnect = true
      raise error
    end

    def master?
      current == master
    end

    private

    def logger
      SlavePools.logger
    end

    def log_errors(error, sp_method, db_method)
      logger.error "[SlavePools] - Error: #{error}"
      logger.error "[SlavePools] - SlavePool Method: #{sp_method}"
      logger.error "[SlavePools] - Master Value: #{master}"
      logger.error "[SlavePools] - Master Depth: #{master_depth}"
      logger.error "[SlavePools] - Current Value: #{current}"
      logger.error "[SlavePools] - Current Pool: #{current_pool}"
      logger.error "[SlavePools] - Current Pool Slaves: #{current_pool.slaves}" if current_pool
      logger.error "[SlavePools] - Current Pool Name: #{current_pool.name}" if current_pool
      logger.error "[SlavePools] - Reconnect Value: #{@reconnect}"
      logger.error "[SlavePools] - Default Pool: #{default_pool}"
      logger.error "[SlavePools] - DB Method: #{db_method}"
    end
  end
end
