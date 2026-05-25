require 'spec_helper'

RSpec.describe Flowy::Result do
  # ---- union type ------------------------------------------------------------

  describe 'union type' do
    it 'Success is a Flowy::Result' do
      expect(Flowy::Success.new).to be_a(described_class)
    end

    it 'Failure is a Flowy::Result' do
      expect(Flowy::Failure.new(error_code: :err)).to be_a(described_class)
    end
  end

  # ---- factory methods -------------------------------------------------------

  describe '.success' do
    it 'returns a Flowy::Success' do
      expect(described_class.success).to be_a(Flowy::Success)
    end

    it 'accepts data' do
      result = described_class.success(data: { id: 1 })
      expect(result.data).to eq({ id: 1 })
    end

    it 'accepts warnings' do
      result = described_class.success(warnings: ['w'])
      expect(result.warnings).to eq(['w'])
    end

    it 'defaults data to empty hash' do
      expect(described_class.success.data).to eq({})
    end
  end

  describe '.failure' do
    it 'returns a Flowy::Failure' do
      expect(described_class.failure(error_code: :err)).to be_a(Flowy::Failure)
    end

    it 'sets error_code' do
      result = described_class.failure(error_code: :not_found)
      expect(result.error_code).to eq(:not_found)
    end

    it 'accepts error_data, error_title, error_description' do
      result = described_class.failure(
        error_code: :err,
        error_data: { field: 'x' },
        error_title: 'T',
        error_description: 'D'
      )
      expect(result.error_data).to eq({ field: 'x' })
      expect(result.error_title).to eq('T')
      expect(result.error_description).to eq('D')
    end

    it 'accepts parent_failure' do
      parent = Flowy::Failure.new(error_code: :parent_err)
      result = described_class.failure(error_code: :child_err, parent_failure: parent)
      expect(result.parent_failure).to equal(parent)
    end
  end

  # ---- .wrap -----------------------------------------------------------------

  describe '.wrap' do
    context 'when the block succeeds' do
      it 'wraps a plain value in a Success with key :value' do
        result = described_class.wrap { 42 }
        expect(result).to be_a(Flowy::Success)
        expect(result.data[:value]).to eq(42)
      end

      it 'wraps a string value' do
        result = described_class.wrap { 'hello' }
        expect(result.data[:value]).to eq('hello')
      end

      it 'wraps nil' do
        result = described_class.wrap { nil }
        expect(result).to be_a(Flowy::Success)
        expect(result.data[:value]).to be_nil
      end

      it 'forwards a Success returned by the block unchanged' do
        inner = Flowy::Success.new(data: { id: 1 })
        result = described_class.wrap { inner }
        expect(result).to equal(inner)
      end

      it 'forwards a Failure returned by the block unchanged' do
        inner = Flowy::Failure.new(error_code: :already_failed)
        result = described_class.wrap { inner }
        expect(result).to equal(inner)
      end

      it 'forwards any Flowy::Result subtype unchanged' do
        inner = Flowy::Success.new
        expect(inner).to be_a(Flowy::Result)
        expect(described_class.wrap { inner }).to equal(inner)
      end
    end

    context 'when the block raises a StandardError' do
      it 'returns a Failure' do
        result = described_class.wrap { raise StandardError, 'boom' }
        expect(result).to be_a(Flowy::Failure)
      end

      it 'uses :wrapped_error as default error_code' do
        result = described_class.wrap { raise 'oops' }
        expect(result.error_code).to eq(:wrapped_error)
      end

      it 'stores error_class and message in error_data' do
        result = described_class.wrap { raise ArgumentError, 'bad arg' }
        expect(result.error_data[:error_class]).to eq('ArgumentError')
        expect(result.error_data[:message]).to eq('bad arg')
      end

      it 'sets error_description to the exception message' do
        result = described_class.wrap { raise RuntimeError, 'runtime issue' }
        expect(result.error_description).to eq('runtime issue')
      end
    end

    context 'with custom error_code:' do
      it 'uses the provided error_code on failure' do
        result = described_class.wrap(error_code: :not_found) { raise 'missing' }
        expect(result.error_code).to eq(:not_found)
      end
    end

    context 'with custom error_title:' do
      it 'sets error_title on the generated Failure' do
        result = described_class.wrap(error_title: 'Lookup failed') { raise 'missing' }
        expect(result.error_title).to eq('Lookup failed')
      end
    end

    context 'with custom rescue: classes' do
      it 'catches the declared exception class' do
        result = described_class.wrap(rescue: [ArgumentError]) { raise ArgumentError, 'bad' }
        expect(result).to be_a(Flowy::Failure)
      end

      it 'does not catch undeclared exception classes' do
        expect {
          described_class.wrap(rescue: [ArgumentError]) { raise RuntimeError, 'not caught' }
        }.to raise_error(RuntimeError, 'not caught')
      end

      it 'catches subclasses of declared exception classes' do
        result = described_class.wrap(rescue: [StandardError]) { raise ZeroDivisionError, 'div 0' }
        expect(result).to be_a(Flowy::Failure)
      end
    end

    context 'with an empty rescue: list' do
      it 'lets all exceptions propagate' do
        expect {
          described_class.wrap(rescue: []) { raise 'never caught' }
        }.to raise_error(RuntimeError, 'never caught')
      end
    end

    context 'with an unknown keyword' do
      it 'raises ArgumentError' do
        expect {
          described_class.wrap(foo: 1) { 'whatever' }
        }.to raise_error(ArgumentError, /unknown keyword: foo/)
      end
    end
  end
end
