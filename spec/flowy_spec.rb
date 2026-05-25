require 'spec_helper'

RSpec.describe Flowy do
  it 'has a VERSION constant' do
    expect(defined?(Flowy::VERSION)).to eq('constant')
  end

  it 'exposes Flowy::Success' do
    expect(defined?(Flowy::Success)).to eq('constant')
  end

  it 'exposes Flowy::Failure' do
    expect(defined?(Flowy::Failure)).to eq('constant')
  end

  it 'exposes Flowy::Concern' do
    expect(defined?(Flowy::Concern)).to eq('constant')
  end

  it 'exposes Flowy::Error' do
    expect(defined?(Flowy::Error)).to eq('constant')
  end

  it 'exposes Flowy::Result' do
    expect(defined?(Flowy::Result)).to eq('constant')
  end

  it 'Success is a Flowy::Result' do
    expect(Flowy::Success.new).to be_a(Flowy::Result)
  end

  it 'Failure is a Flowy::Result' do
    expect(Flowy::Failure.new(error_code: :err)).to be_a(Flowy::Result)
  end
end
