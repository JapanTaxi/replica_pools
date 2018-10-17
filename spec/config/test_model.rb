class TestModel < ActiveRecord::Base
  use_replica_pools :main
end
