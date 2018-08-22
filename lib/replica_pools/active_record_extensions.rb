module ReplicaPools
  module ActiveRecordExtensions
    def self.included(base)
      base.send :extend, ClassMethods
    end

    def reload(options = nil)
      return super unless self.class.replica_pools_enabled?
      self.class.with_leader { super }
    end

    module ClassMethods
      def hijack_connection
        class << self
          alias_method :connection, :connection_proxy if ReplicaPools.config.enabled?
        end
      end

      def use_replica_pools(db_name)
        @replica_pools_db_name = db_name
        ReplicaPools.create_proxy(self, db_name)
        hijack_connection
      end

      def connection_proxy
        ReplicaPools.fetch_proxy(replica_pools_db_name)
      end

      def with_pool(*a)
        connection_proxy.with_pool(*a){ yield }
      end

      def with_leader
        connection_proxy.with_leader{ yield }
      end

      def current_connection
        connection_proxy.current
      end

      def next_replica!
        connection_proxy.next_replica!
      end

      def replica_pools_enabled?
        !!replica_pools_db_name
      end

      def replica_pools_db_name
        replica_pools_own_db_name || replica_pools_closest_ancestor_db_name
      end

      def replica_pools_own_db_name
        @replica_pools_db_name
      end

      def replica_pools_closest_ancestor_db_name
        ancestors.select{ |k| k <= ActiveRecord::Base }.map(&:replica_pools_own_db_name).compact.first
      end

      # Make sure transactions run on leader
      def transaction(options = {}, &block)
        return super unless replica_pools_enabled?
        self.with_leader { super }
      end
    end
  end
end
