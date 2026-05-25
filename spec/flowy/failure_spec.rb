require 'spec_helper'

RSpec.describe Flowy::Failure do
  describe '#initialize' do
    it 'requires error_code' do
      expect { described_class.new }.to raise_error(ArgumentError)
    end

    it 'sets error_code' do
      result = described_class.new(error_code: :not_found)
      expect(result.error_code).to eq(:not_found)
    end

    it 'defaults error_data to an empty hash' do
      result = described_class.new(error_code: :err)
      expect(result.error_data).to eq({})
    end

    it 'defaults error_title to nil' do
      result = described_class.new(error_code: :err)
      expect(result.error_title).to be_nil
    end

    it 'defaults error_description to nil' do
      result = described_class.new(error_code: :err)
      expect(result.error_description).to be_nil
    end

    it 'defaults parent_failure to nil' do
      result = described_class.new(error_code: :err)
      expect(result.parent_failure).to be_nil
    end

    it 'accepts all optional parameters' do
      parent = described_class.new(error_code: :parent_err)
      result = described_class.new(
        error_code: :child_err,
        error_data: { field: 'name' },
        error_title: 'Title',
        error_description: 'Description',
        parent_failure: parent
      )
      expect(result.error_code).to eq(:child_err)
      expect(result.error_data).to eq({ field: 'name' })
      expect(result.error_title).to eq('Title')
      expect(result.error_description).to eq('Description')
      expect(result.parent_failure).to eq(parent)
    end
  end

  describe '#success?' do
    it 'returns false' do
      expect(described_class.new(error_code: :err).success?).to be false
    end
  end

  describe '#failure?' do
    it 'returns true' do
      expect(described_class.new(error_code: :err).failure?).to be true
    end
  end

  describe '#to_hash' do
    subject(:result) do
      described_class.new(
        error_code: :validation_error,
        error_data: { field: 'email' },
        error_title: 'Error',
        error_description: 'Invalid email'
      )
    end

    it 'includes success: false' do
      expect(result.to_hash[:success]).to be false
    end

    it 'includes error_code' do
      expect(result.to_hash[:error_code]).to eq(:validation_error)
    end

    it 'includes error_data' do
      expect(result.to_hash[:error_data]).to eq({ field: 'email' })
    end

    it 'includes error_title' do
      expect(result.to_hash[:error_title]).to eq('Error')
    end

    it 'includes error_description' do
      expect(result.to_hash[:error_description]).to eq('Invalid email')
    end

    it 'returns the full structure' do
      expect(result.to_hash).to eq({
        success: false,
        error_code: :validation_error,
        error_data: { field: 'email' },
        error_title: 'Error',
        error_description: 'Invalid email'
      })
    end
  end

  describe '#on_failure' do
    it 'yields the result object' do
      result  = described_class.new(
        error_code: :not_found,
        error_data: { id: 1 },
        error_title: 'Not found',
        error_description: 'Missing'
      )
      yielded = nil
      result.on_failure { |r| yielded = r }
      expect(yielded).to equal(result)
    end

    it 'returns self' do
      result = described_class.new(error_code: :err)
      expect(result.on_failure {}).to equal(result)
    end
  end

  describe '#on_success' do
    it 'does not yield' do
      expect { |b| described_class.new(error_code: :err).on_success(&b) }.not_to yield_control
    end

    it 'returns self' do
      result = described_class.new(error_code: :err)
      expect(result.on_success {}).to equal(result)
    end
  end

  describe 'chaining on_success and on_failure' do
    it 'only executes on_failure block' do
      called_success = false
      called_failure = false
      described_class.new(error_code: :err)
        .on_success { called_success = true }
        .on_failure { called_failure = true }
      expect(called_success).to be false
      expect(called_failure).to be true
    end
  end

  describe '#and_then' do
    it 'does not yield' do
      expect { |b| described_class.new(error_code: :err).and_then(&b) }.not_to yield_control
    end

    it 'returns self' do
      result = described_class.new(error_code: :err)
      expect(result.and_then { Flowy::Success.new }).to equal(result)
    end
  end

  describe '#or_else' do
    it 'yields self to the block' do
      result  = described_class.new(error_code: :err)
      yielded = nil
      result.or_else { |r| yielded = r; Flowy::Success.new }
      expect(yielded).to equal(result)
    end

    it 'returns the result of the block when it is a Success' do
      recovery = Flowy::Success.new(data: { recovered: true })
      outcome  = described_class.new(error_code: :err).or_else { recovery }
      expect(outcome).to equal(recovery)
    end

    it 'returns the result of the block when it is a Failure' do
      other = described_class.new(error_code: :other_err)
      outcome = described_class.new(error_code: :err).or_else { other }
      expect(outcome).to equal(other)
    end

    it 'raises TypeError if the block does not return a Success or Failure' do
      expect { described_class.new(error_code: :err).or_else { 42 } }.to raise_error(TypeError, /Flowy::Success or Flowy::Failure/)
    end
  end

  describe '#failures_chain' do
    it 'returns an array containing only itself when there is no parent_failure' do
      failure = described_class.new(error_code: :leaf)
      expect(failure.failures_chain).to eq([failure])
    end

    it 'returns the chain from parent to child' do
      parent = described_class.new(error_code: :parent_err)
      child  = described_class.new(error_code: :child_err, parent_failure: parent)
      expect(child.failures_chain).to eq([parent, child])
    end

    it 'handles chains with multiple levels' do
      root = described_class.new(error_code: :root)
      mid  = described_class.new(error_code: :mid, parent_failure: root)
      leaf = described_class.new(error_code: :leaf, parent_failure: mid)
      expect(leaf.failures_chain).to eq([root, mid, leaf])
    end
  end

  describe '#merge_data' do
    subject(:result) do
      described_class.new(
        error_code: :err,
        error_data: { field: 'email' },
        error_title: 'Error',
        error_description: 'Invalid'
      )
    end

    it 'returns a new Failure with merged error_data' do
      merged = result.merge_data(context: 'CreateUser')
      expect(merged.error_data).to eq({ field: 'email', context: 'CreateUser' })
    end

    it 'does not mutate the original' do
      result.merge_data(context: 'x')
      expect(result.error_data).to eq({ field: 'email' })
    end

    it 'preserves error_code, error_title, error_description and parent_failure' do
      parent = described_class.new(error_code: :parent)
      r = described_class.new(error_code: :err, error_data: {}, error_title: 'T',
                              error_description: 'D', parent_failure: parent)
      merged = r.merge_data(x: 1)
      expect(merged.error_code).to eq(:err)
      expect(merged.error_title).to eq('T')
      expect(merged.error_description).to eq('D')
      expect(merged.parent_failure).to equal(parent)
    end

    it 'lets the given hash overwrite existing keys' do
      merged = result.merge_data(field: 'name')
      expect(merged.error_data[:field]).to eq('name')
    end

    it 'performs a deep merge on nested hashes' do
      r = described_class.new(error_code: :err, error_data: { meta: { x: 1, y: 2 } })
      merged = r.merge_data(meta: { y: 99, z: 3 })
      expect(merged.error_data[:meta]).to eq({ x: 1, y: 99, z: 3 })
    end

    it 'recursively deep-merges hashes nested 3+ levels deep' do
      r = described_class.new(error_code: :err, error_data: { ctx: { foo: { x: 1, y: 2 } } })
      merged = r.merge_data(ctx: { foo: { y: 99, z: 3 } })
      expect(merged.error_data[:ctx][:foo]).to eq({ x: 1, y: 99, z: 3 })
    end

    it 'accepts a block yielding current error_data' do
      merged = result.merge_data { |d| { original_field: d[:field] } }
      expect(merged.error_data[:original_field]).to eq('email')
    end

    it 'raises ArgumentError when the argument is not a Hash' do
      expect { result.merge_data(42) }.to raise_error(ArgumentError, /Hash/)
    end

    it 'raises ArgumentError when the block returns a non-Hash' do
      expect { result.merge_data { nil } }.to raise_error(ArgumentError, /Hash/)
    end

    it 'returns a Failure' do
      expect(result.merge_data(x: 1)).to be_a(described_class)
    end
  end

  describe '#map_failure' do
    subject(:original) do
      described_class.new(
        error_code:        :service_b_error,
        error_data:        { detail: 'bad gateway' },
        error_title:       'Service B failed',
        error_description: 'Downstream error'
      )
    end

    # --- block form -----------------------------------------------------------

    context 'block form' do
      it 'returns a new Failure produced by the block' do
        result = original.map_failure { |_f| described_class.new(error_code: :service_a_error) }
        expect(result).to be_a(described_class)
        expect(result.error_code).to eq(:service_a_error)
      end

      it 'yields self to the block' do
        yielded = nil
        original.map_failure { |f| yielded = f; described_class.new(error_code: :x) }
        expect(yielded).to equal(original)
      end

      it 'sets parent_failure to self automatically when the block omits it' do
        result = original.map_failure { |_f| described_class.new(error_code: :wrapped) }
        expect(result.parent_failure).to equal(original)
      end

      it 'preserves an explicit parent_failure set by the caller in the block' do
        explicit_parent = described_class.new(error_code: :explicit_parent)
        result = original.map_failure do |_f|
          described_class.new(error_code: :wrapped, parent_failure: explicit_parent)
        end
        expect(result.parent_failure).to equal(explicit_parent)
      end

      it 'does not mutate the original failure' do
        original.map_failure { |_f| described_class.new(error_code: :wrapped) }
        expect(original.error_code).to eq(:service_b_error)
        expect(original.parent_failure).to be_nil
      end

      it 'builds a failures_chain accessible on the outer failure' do
        inner  = described_class.new(error_code: :inner)
        outer  = inner.map_failure { |_f| described_class.new(error_code: :outer) }
        expect(outer.failures_chain).to eq([inner, outer])
      end

      it 'supports multi-level chaining via failures_chain' do
        root   = described_class.new(error_code: :root)
        mid    = root.map_failure   { |_f| described_class.new(error_code: :mid) }
        leaf   = mid.map_failure    { |_f| described_class.new(error_code: :leaf) }
        expect(leaf.failures_chain.map(&:error_code)).to eq([:root, :mid, :leaf])
      end

      it 'raises TypeError when the block returns a Success' do
        expect {
          original.map_failure { Flowy::Success.new }
        }.to raise_error(TypeError, /map_failure block must return a Flowy::Failure/)
      end

      it 'raises TypeError when the block returns a non-Result value' do
        expect {
          original.map_failure { 'not a result' }
        }.to raise_error(TypeError, /map_failure block must return a Flowy::Failure/)
      end

      it 'is chainable with on_failure' do
        log = []
        original
          .map_failure { |f| described_class.new(error_code: :wrapped, parent_failure: f) }
          .on_failure  { |r| log << r.error_code }
        expect(log).to eq([:wrapped])
      end
    end

    # --- keyword-args shorthand form ------------------------------------------

    context 'shorthand form (keyword args, no block)' do
      it 'returns a new Failure with the given error_code' do
        result = original.map_failure(error_code: :service_a_error)
        expect(result).to be_a(described_class)
        expect(result.error_code).to eq(:service_a_error)
      end

      it 'sets parent_failure to self automatically' do
        result = original.map_failure(error_code: :wrapped)
        expect(result.parent_failure).to equal(original)
      end

      it 'accepts error_data' do
        result = original.map_failure(error_code: :wrapped, error_data: { context: 'ServiceA' })
        expect(result.error_data).to eq({ context: 'ServiceA' })
      end

      it 'accepts error_title' do
        result = original.map_failure(error_code: :wrapped, error_title: 'Outer error')
        expect(result.error_title).to eq('Outer error')
      end

      it 'accepts error_description' do
        result = original.map_failure(error_code: :wrapped, error_description: 'See parent for details')
        expect(result.error_description).to eq('See parent for details')
      end

      it 'defaults error_data to empty hash when omitted' do
        result = original.map_failure(error_code: :wrapped)
        expect(result.error_data).to eq({})
      end

      it 'does not mutate the original failure' do
        original.map_failure(error_code: :wrapped)
        expect(original.error_code).to eq(:service_b_error)
        expect(original.parent_failure).to be_nil
      end

      it 'raises ArgumentError when error_code is omitted' do
        expect {
          original.map_failure
        }.to raise_error(ArgumentError, /error_code/)
      end

      it 'builds a failures_chain accessible on the outer failure' do
        inner = described_class.new(error_code: :inner)
        outer = inner.map_failure(error_code: :outer)
        expect(outer.failures_chain).to eq([inner, outer])
      end
    end
  end

  describe '#raise!' do
    subject(:result) do
      described_class.new(
        error_code:        :payment_declined,
        error_data:        { gateway: 'stripe' },
        error_title:       'Payment declined',
        error_description: 'The card was declined'
      )
    end

    it 'raises a Flowy::Error' do
      expect { result.raise! }.to raise_error(Flowy::Error)
    end

    it 'the raised error carries the correct code' do
      expect { result.raise! }.to raise_error(Flowy::Error) { |e|
        expect(e.code).to eq(:payment_declined)
      }
    end

    it 'the raised error carries title, detail and meta' do
      expect { result.raise! }.to raise_error(Flowy::Error) { |e|
        expect(e.title).to eq('Payment declined')
        expect(e.detail).to eq('The card was declined')
        expect(e.meta).to eq({ gateway: 'stripe' })
      }
    end

    it 'the raised error is rescuable as StandardError' do
      rescued = nil
      begin
        result.raise!
      rescue StandardError => e
        rescued = e
      end
      expect(rescued).to be_a(Flowy::Error)
    end

    it 'the raised Flowy::Error can be converted back to a Failure' do
      begin
        result.raise!
      rescue Flowy::Error => e
        recovered = e.to_failure
        expect(recovered.error_code).to eq(:payment_declined)
        expect(recovered.error_data).to eq({ gateway: 'stripe' })
      end
    end
  end

  describe '#tap' do
    it 'yields self' do
      result  = described_class.new(error_code: :err)
      yielded = nil
      result.tap { |r| yielded = r }
      expect(yielded).to equal(result)
    end

    it 'returns self regardless of the block return value' do
      result = described_class.new(error_code: :err)
      expect(result.tap { 'ignored' }).to equal(result)
    end

    it 'is chainable with on_failure' do
      log    = []
      described_class.new(error_code: :err)
        .tap         { |r| log << r.error_code }
        .on_failure  { |r| log << :handled }
      expect(log).to eq([:err, :handled])
    end
  end
end
