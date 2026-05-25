require 'spec_helper'

RSpec.describe Flowy::Success do
  describe '#initialize' do
    it 'defaults data to an empty hash' do
      result = described_class.new
      expect(result.data).to eq({})
    end

    it 'defaults warnings to an empty array' do
      result = described_class.new
      expect(result.warnings).to eq([])
    end

    it 'accepts custom data' do
      result = described_class.new(data: { user: 'Alice' })
      expect(result.data).to eq({ user: 'Alice' })
    end

    it 'accepts custom warnings' do
      result = described_class.new(warnings: ['warning'])
      expect(result.warnings).to eq(['warning'])
    end
  end

  describe '#success?' do
    it 'returns true' do
      expect(described_class.new.success?).to be true
    end
  end

  describe '#failure?' do
    it 'returns false' do
      expect(described_class.new.failure?).to be false
    end
  end

  describe '#to_hash' do
    it 'includes success: true' do
      expect(described_class.new.to_hash[:success]).to be true
    end

    it 'includes data' do
      result = described_class.new(data: { id: 1 })
      expect(result.to_hash[:data]).to eq({ id: 1 })
    end

    it 'includes warnings' do
      result = described_class.new(warnings: ['warn'])
      expect(result.to_hash[:warnings]).to eq(['warn'])
    end

    it 'returns the full structure' do
      result = described_class.new(data: { id: 42 }, warnings: ['w1'])
      expect(result.to_hash).to eq({ success: true, data: { id: 42 }, warnings: ['w1'] })
    end
  end

  describe '#+' do
    it 'merges the data of two Success objects' do
      a = described_class.new(data: { x: 1 })
      b = described_class.new(data: { y: 2 })
      result = a + b
      expect(result.data).to eq({ x: 1, y: 2 })
    end

    it 'lets the right operand overwrite duplicate keys' do
      a = described_class.new(data: { x: 1 })
      b = described_class.new(data: { x: 99 })
      result = a + b
      expect(result.data[:x]).to eq(99)
    end

    it 'performs a deep merge on nested hashes' do
      a = described_class.new(data: { nested: { a: 1, b: 2 } })
      b = described_class.new(data: { nested: { b: 99, c: 3 } })
      result = a + b
      expect(result.data[:nested]).to eq({ a: 1, b: 99, c: 3 })
    end

    it 'recursively deep-merges hashes nested 3+ levels deep' do
      a = described_class.new(data: { meta: { nested: { x: 1, y: 2 } } })
      b = described_class.new(data: { meta: { nested: { y: 99, z: 3 } } })
      result = a + b
      expect(result.data[:meta][:nested]).to eq({ x: 1, y: 99, z: 3 })
    end

    it 'returns a new Success object' do
      a = described_class.new(data: { x: 1 })
      b = described_class.new(data: { y: 2 })
      expect(a + b).to be_a(described_class)
    end
  end

  describe '#on_success' do
    it 'yields the result object' do
      result   = described_class.new(data: { x: 1 }, warnings: ['w'])
      yielded  = nil
      result.on_success { |r| yielded = r }
      expect(yielded).to equal(result)
    end

    it 'returns self' do
      result = described_class.new
      expect(result.on_success {}).to equal(result)
    end
  end

  describe '#on_failure' do
    it 'does not yield' do
      expect { |b| described_class.new.on_failure(&b) }.not_to yield_control
    end

    it 'returns self' do
      result = described_class.new
      expect(result.on_failure {}).to equal(result)
    end
  end

  describe 'chaining on_success and on_failure' do
    it 'only executes on_success block' do
      called_success = false
      called_failure = false
      described_class.new
        .on_success { called_success = true }
        .on_failure { called_failure = true }
      expect(called_success).to be true
      expect(called_failure).to be false
    end
  end

  describe '#and_then' do
    it 'yields self to the block' do
      result   = described_class.new(data: { x: 1 })
      yielded  = nil
      result.and_then { |r| yielded = r; r }
      expect(yielded).to equal(result)
    end

    it 'returns the result of the block when it is a Success' do
      next_result = described_class.new(data: { y: 2 })
      outcome = described_class.new.and_then { next_result }
      expect(outcome).to equal(next_result)
    end

    it 'returns the result of the block when it is a Failure' do
      failure = Flowy::Failure.new(error_code: :err)
      outcome = described_class.new.and_then { failure }
      expect(outcome).to equal(failure)
    end

    it 'raises TypeError if the block does not return a Success or Failure' do
      expect { described_class.new.and_then { 'bad' } }.to raise_error(TypeError, /Flowy::Success or Flowy::Failure/)
    end

    it 'chains multiple steps, passing data along' do
      outcome = described_class.new(data: { a: 1 })
        .and_then { |r| described_class.new(data: r.data.merge(b: 2)) }
        .and_then { |r| described_class.new(data: r.data.merge(c: 3)) }
      expect(outcome.data).to eq({ a: 1, b: 2, c: 3 })
    end

    it 'short-circuits on the first Failure in a chain' do
      second_called = false
      outcome = described_class.new
        .and_then { Flowy::Failure.new(error_code: :step_failed) }
        .and_then { second_called = true; described_class.new }
      expect(outcome).to be_a(Flowy::Failure)
      expect(second_called).to be false
    end
  end

  describe '#or_else' do
    it 'does not yield' do
      expect { |b| described_class.new.or_else(&b) }.not_to yield_control
    end

    it 'returns self' do
      result = described_class.new
      expect(result.or_else { Flowy::Failure.new(error_code: :err) }).to equal(result)
    end
  end

  describe '#merge_data' do
    subject(:result) { described_class.new(data: { a: 1 }, warnings: ['w']) }

    it 'returns a new Success with merged data' do
      merged = result.merge_data(b: 2)
      expect(merged.data).to eq({ a: 1, b: 2 })
    end

    it 'does not mutate the original' do
      result.merge_data(b: 2)
      expect(result.data).to eq({ a: 1 })
    end

    it 'preserves warnings' do
      expect(result.merge_data(b: 2).warnings).to eq(['w'])
    end

    it 'lets the given hash overwrite existing keys' do
      merged = result.merge_data(a: 99)
      expect(merged.data[:a]).to eq(99)
    end

    it 'performs a deep merge on nested hashes' do
      r = described_class.new(data: { nested: { x: 1, y: 2 } })
      merged = r.merge_data(nested: { y: 99, z: 3 })
      expect(merged.data[:nested]).to eq({ x: 1, y: 99, z: 3 })
    end

    it 'recursively deep-merges hashes nested 3+ levels deep' do
      r = described_class.new(data: { a: { b: { c: 1, d: 2 } } })
      merged = r.merge_data(a: { b: { d: 99, e: 3 } })
      expect(merged.data[:a][:b]).to eq({ c: 1, d: 99, e: 3 })
    end

    it 'accepts a block yielding current data' do
      merged = result.merge_data { |d| { double_a: d[:a] * 2 } }
      expect(merged.data[:double_a]).to eq(2)
    end

    it 'raises ArgumentError when the argument is not a Hash' do
      expect { result.merge_data('bad') }.to raise_error(ArgumentError, /Hash/)
    end

    it 'raises ArgumentError when the block returns a non-Hash' do
      expect { result.merge_data { 'bad' } }.to raise_error(ArgumentError, /Hash/)
    end

    it 'returns a Success' do
      expect(result.merge_data(b: 2)).to be_a(described_class)
    end
  end

  describe '#map_failure' do
    it 'returns self without executing the block' do
      result  = described_class.new(data: { x: 1 })
      called  = false
      outcome = result.map_failure { called = true; Flowy::Failure.new(error_code: :should_not_run) }
      expect(outcome).to equal(result)
      expect(called).to be false
    end

    it 'returns self with the shorthand form (no block)' do
      result  = described_class.new(data: { x: 1 })
      outcome = result.map_failure(error_code: :irrelevant)
      expect(outcome).to equal(result)
    end

    it 'is chainable — and_then still executes after map_failure on a Success' do
      outcome = described_class.new(data: { n: 1 })
        .map_failure(error_code: :irrelevant)
        .and_then { |r| described_class.new(data: r.data.merge(n: r.data[:n] + 1)) }
      expect(outcome.data[:n]).to eq(2)
    end
  end

  describe '#raise!' do
    it 'returns self without raising' do
      result  = described_class.new(data: { x: 1 })
      outcome = nil
      expect { outcome = result.raise! }.not_to raise_error
      expect(outcome).to equal(result)
    end

    it 'is chainable — and_then still executes after raise! on a Success' do
      outcome = described_class.new(data: { n: 1 })
        .raise!
        .and_then { |r| described_class.new(data: r.data.merge(n: r.data[:n] + 1)) }
      expect(outcome.data[:n]).to eq(2)
    end
  end

  describe '#tap' do
    it 'yields self' do
      result  = described_class.new(data: { x: 1 })
      yielded = nil
      result.tap { |r| yielded = r }
      expect(yielded).to equal(result)
    end

    it 'returns self regardless of the block return value' do
      result = described_class.new
      expect(result.tap { 'ignored' }).to equal(result)
    end

    it 'does not modify data' do
      result = described_class.new(data: { x: 1 })
      # block return value must not affect the result object
      new_result = result.tap { |r| 'ignored' }
      expect(new_result.data).to eq({ x: 1 })
    end

    it 'is chainable with and_then' do
      log    = []
      outcome = described_class.new(data: { n: 1 })
        .tap    { |r| log << :tapped }
        .and_then { |r| described_class.new(data: r.data.merge(n: r.data[:n] + 1)) }
      expect(log).to eq([:tapped])
      expect(outcome.data[:n]).to eq(2)
    end
  end
end
