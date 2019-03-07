module ReplicaPools
  # duck-types with ActiveRecord::ConnectionAdapters::QueryCache
  # but relies on ActiveRecord::Base.query_cache for state so we
  # don't fragment the cache across multiple connections
  #
  # we could use more of ActiveRecord's QueryCache if it only
  # used accessors for its internal ivars.
  module QueryCache
    query_cache_methods = ActiveRecord::ConnectionAdapters::QueryCache.instance_methods(false)

    # these methods can all use the leader connection
    (query_cache_methods - [:select_all]).each do |method_name|
      module_eval <<-END, __FILE__, __LINE__ + 1
        def #{method_name}(*a, &b)
          route_to(leader, :#{method_name}, *a, &b)
        end
      END
    end

    # select_all is trickier. it needs to use the leader
    # connection for cache logic, but ultimately pass its query
    # through to whatever connection is current.
    def select_all(*args)
      # there may be more args for Rails 5.0+, but we only care about arel, name, and binds for caching.
      relation, name, raw_binds = args
      raw_binds ||= [] # emulate default argument behavior

      if !query_cache_enabled || locked?(relation)
        return route_to(current, :select_all, *args)
      end

      # duplicate binds_from_relation behavior introduced in 4.2.
      if raw_binds.blank? && relation.is_a?(ActiveRecord::Relation)
        arel, binds = relation.arel, relation.bind_values
      else
        arel, binds = relation, raw_binds
      end

      if Gem::Version.new(ActiveRecord.version) < Gem::Version.new('5.1')
        sql = to_sql(arel, binds)
        args[0] = sql
        args[2] = binds
        cache_sql(sql, binds) { route_to(current, :select_all, *args) }
      else
        sql, binds = to_sql_and_binds(arel, binds) # `to_sql` doesnt return binds
        args[0] = sql
        args[2] = binds
        cache_sql(sql, name, binds) { route_to(current, :select_all, *args) }
      end
    end

    # these can use the unsafe delegation built into ConnectionProxy
    # [:insert, :update, :delete]
  end
end
