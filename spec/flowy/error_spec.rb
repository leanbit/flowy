require 'spec_helper'

RSpec.describe Flowy::Error do
  subject(:error) do
    described_class.new(
      code: :not_found,
      title: 'Not found',
      detail: 'The resource does not exist',
      meta: { id: 42 }
    )
  end

  it 'is a subclass of StandardError' do
    expect(described_class.superclass).to eq(StandardError)
  end

  it 'can be rescued as StandardError' do
    expect { raise error }.to raise_error(StandardError)
  end

  it 'can be rescued as Flowy::Error' do
    expect { raise error }.to raise_error(described_class)
  end

  describe '#initialize' do
    it 'sets code' do
      expect(error.code).to eq(:not_found)
    end

    it 'sets title' do
      expect(error.title).to eq('Not found')
    end

    it 'sets detail' do
      expect(error.detail).to eq('The resource does not exist')
    end

    it 'sets meta' do
      expect(error.meta).to eq({ id: 42 })
    end

    it 'defaults title to nil' do
      e = described_class.new(code: :err)
      expect(e.title).to be_nil
    end

    it 'defaults detail to nil' do
      e = described_class.new(code: :err)
      expect(e.detail).to be_nil
    end

    it 'defaults meta to nil' do
      e = described_class.new(code: :err)
      expect(e.meta).to be_nil
    end
  end

  describe '#message' do
    it 'contains only code when title and detail are nil' do
      e = described_class.new(code: :generic)
      expect(e.message).to eq('generic')
    end

    it 'joins code, title and detail' do
      expect(error.message).to eq('not_found - Not found: The resource does not exist')
    end

    it 'contains code and title only when detail is nil' do
      e = described_class.new(code: :err, title: 'Title only')
      expect(e.message).to eq('err - Title only')
    end

    it 'contains code and detail only when title is nil' do
      e = described_class.new(code: :err, detail: 'Detail only')
      expect(e.message).to eq('err - Detail only')
    end

    it 'treats an empty title string as absent' do
      e = described_class.new(code: :err, title: '', detail: 'Detail')
      expect(e.message).to eq('err - Detail')
    end

    it 'treats an empty detail string as absent' do
      e = described_class.new(code: :err, title: 'Title', detail: '')
      expect(e.message).to eq('err - Title')
    end
  end

  describe '.initialize_from_failure' do
    let(:failure) do
      Flowy::Failure.new(
        error_code: :unauthorized,
        error_data: { role: 'guest' },
        error_title: 'Unauthorized',
        error_description: 'Access denied'
      )
    end

    subject(:error_from_failure) { described_class.initialize_from_failure(failure: failure) }

    it 'returns a Flowy::Error' do
      expect(error_from_failure).to be_a(described_class)
    end

    it 'maps error_code to code' do
      expect(error_from_failure.code).to eq(:unauthorized)
    end

    it 'maps error_title to title' do
      expect(error_from_failure.title).to eq('Unauthorized')
    end

    it 'maps error_description to detail' do
      expect(error_from_failure.detail).to eq('Access denied')
    end

    it 'maps error_data to meta' do
      expect(error_from_failure.meta).to eq({ role: 'guest' })
    end

    it 'raises ArgumentError when not given a Flowy::Failure' do
      expect { described_class.initialize_from_failure(failure: 'string') }
        .to raise_error(ArgumentError, /Flowy::Failure/)
    end

    it 'raises ArgumentError for nil' do
      expect { described_class.initialize_from_failure(failure: nil) }
        .to raise_error(ArgumentError)
    end
  end

  describe '#to_failure' do
    it 'returns a Flowy::Failure' do
      expect(error.to_failure).to be_a(Flowy::Failure)
    end

    it 'maps code to error_code' do
      expect(error.to_failure.error_code).to eq(:not_found)
    end

    it 'maps title to error_title' do
      expect(error.to_failure.error_title).to eq('Not found')
    end

    it 'maps detail to error_description' do
      expect(error.to_failure.error_description).to eq('The resource does not exist')
    end

    it 'maps meta to error_data' do
      expect(error.to_failure.error_data).to eq({ id: 42 })
    end

    it 'returns error_data as {} when meta was not provided' do
      e = described_class.new(code: :boom)
      expect(e.to_failure.error_data).to eq({})
    end

    it 'preserves the Failure#error_data invariant after a Failure -> Error -> Failure roundtrip' do
      original  = Flowy::Failure.new(error_code: :boom)
      recovered = described_class.initialize_from_failure(failure: original).to_failure
      expect(recovered.error_data).to eq({})
    end
  end

  describe '#to_hash' do
    it 'includes success: false' do
      expect(error.to_hash[:success]).to be false
    end

    it 'includes error_code' do
      expect(error.to_hash[:error_code]).to eq(:not_found)
    end

    it 'is consistent with to_failure#to_hash' do
      expect(error.to_hash).to eq(error.to_failure.to_hash)
    end
  end
end
