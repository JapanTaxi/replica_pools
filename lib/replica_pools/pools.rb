require 'delegate'

module ReplicaPools
  class Pools < ::SimpleDelegator
    include Enumerable

    def initialize
      pools = Hash.new {|h, k| h[k] = {}}
      pool_configurations.group_by{|_, db_name, _, _| db_name }.each do |db_name, db_set|
        db_set.group_by{|_, _, pool_name, _| pool_name }.each do |pool_name, pool_set|
          pools[db_name.to_sym][pool_name.to_sym] = ReplicaPools::Pool.new(
            pool_name,
            pool_set.map{ |conn_name, _, _, replica_name|
              connection_class(db_name, pool_name, replica_name, conn_name).tap do |connection|
                if connection.connection_config['host']
                  connection.connection.host_name = connection.connection_config['host']
                end
              end
            }
          )
        end
      end
      super pools
    end

    private

    # finds valid pool configs
    def pool_configurations
      ActiveRecord::Base.configurations.map do |name, config|
        next unless name.to_s =~ /#{ReplicaPools.config.environment}_db_(.*)_pool_(.*)_name_(.*)/
        [name, $1, $2, $3]
      end.compact
    end

    # generates a unique ActiveRecord::Base subclass for a single replica
    def connection_class(db_name, pool_name, replica_name, connection_name)
      class_name = "#{db_name.camelize}#{pool_name.camelize}#{replica_name.camelize}"
      return ReplicaPools.const_get(class_name) if ReplicaPools.const_defined?(class_name)

      ReplicaPools.module_eval %Q{
        class #{class_name} < ActiveRecord::Base
          self.abstract_class = true
          establish_connection :#{connection_name}
          def self.connection_config
            configurations[#{connection_name.to_s.inspect}]
          end
        end
      }, __FILE__, __LINE__
      ReplicaPools.const_get(class_name)
    end
  end
end
