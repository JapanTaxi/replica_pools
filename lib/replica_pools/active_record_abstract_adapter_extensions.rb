module ReplicaPools
  module ActiveRecordAbstractAdapterExtensions
    attr_accessor :host_name

    def log(sql, name = "SQL", *other_args, &block)
      name = "[ReplicaPools: #{host_name}] #{name}" if host_name
      super(sql, name, *other_args, &block)
    end
  end
end
