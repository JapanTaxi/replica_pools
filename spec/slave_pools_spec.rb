require_relative 'spec_helper'
require_relative 'config/test_model'

describe ReplicaPools do

  before(:each) do
    ReplicaPools.pools[:main].each{|_, pool| pool.reset }
    @proxy = ReplicaPools.proxy(ActiveRecord::Base, :main)
  end

  it 'should delegate next_replica! call to connection proxy' do
    @proxy.should_receive(:next_replica!).exactly(1)
    TestModel.next_replica!
  end

  it 'should delegate with_pool call to connection proxy' do
    @proxy.should_receive(:with_pool).exactly(1)
    TestModel.with_pool('test')
  end

  it 'should delegate with_leader call to connection proxy' do
    @proxy.should_receive(:with_leader).exactly(1)
    TestModel.with_leader
  end
end

