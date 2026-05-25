require 'spec_helper'

RSpec.describe 'Enumerable#all_success' do
  let(:ok)   { ->(n) { Flowy::Result.success(data: { value: n }) } }
  let(:fail) { ->(n) { Flowy::Result.failure(error_code: :bad, error_data: { value: n }) } }

  context 'when all elements produce Success' do
    it 'returns a Flowy::Success' do
      result = [1, 2, 3].all_success { |n| ok.call(n) }
      expect(result).to be_a(Flowy::Success)
    end

    it 'collects all partials in data[:results]' do
      result = [1, 2, 3].all_success { |n| ok.call(n) }
      expect(result.data[:results].size).to eq(3)
      expect(result.data[:results]).to all(be_a(Flowy::Success))
    end

    it 'returns Success with an empty results array for an empty collection' do
      result = [].all_success { |n| ok.call(n) }
      expect(result).to be_a(Flowy::Success)
      expect(result.data[:results]).to eq([])
    end
  end

  context 'when at least one element produces a Failure' do
    it 'returns a Flowy::Failure' do
      result = [1, 2, 3].all_success { |n| n == 2 ? fail.call(n) : ok.call(n) }
      expect(result).to be_a(Flowy::Failure)
    end

    it 'uses :partial_failure as the error_code' do
      result = [1, 2].all_success { |n| fail.call(n) }
      expect(result.error_code).to eq(:partial_failure)
    end

    it 'collects all partials (Success and Failure) in error_data[:results]' do
      result = [1, 2, 3].all_success { |n| n == 2 ? fail.call(n) : ok.call(n) }
      expect(result.error_data[:results].size).to eq(3)
      expect(result.error_data[:results][0]).to be_a(Flowy::Success)
      expect(result.error_data[:results][1]).to be_a(Flowy::Failure)
      expect(result.error_data[:results][2]).to be_a(Flowy::Success)
    end

    it 'returns Failure even if only one element fails' do
      result = [1, 2, 3].all_success { |n| n == 3 ? fail.call(n) : ok.call(n) }
      expect(result).to be_a(Flowy::Failure)
    end

    it 'returns Failure when all elements fail' do
      result = [1, 2, 3].all_success { |n| fail.call(n) }
      expect(result).to be_a(Flowy::Failure)
      expect(result.error_data[:results]).to all(be_a(Flowy::Failure))
    end
  end

  context 'when the block returns an invalid type' do
    it 'raises TypeError' do
      expect {
        [1].all_success { |_n| 'not a result' }
      }.to raise_error(TypeError, /all_success\/any_success block must return a Flowy::Result/)
    end
  end

  context 'on a generic Enumerable (not just Array)' do
    it 'works on a Range' do
      result = (1..3).all_success { |n| ok.call(n) }
      expect(result).to be_a(Flowy::Success)
      expect(result.data[:results].size).to eq(3)
    end

    it 'works on a Hash (iterating key-value pairs)' do
      result = { a: 1, b: 2 }.all_success { |_pair| ok.call(nil) }
      expect(result).to be_a(Flowy::Success)
    end
  end
end

RSpec.describe 'Enumerable#any_success' do
  let(:ok)   { ->(n) { Flowy::Result.success(data: { value: n }) } }
  let(:fail) { ->(n) { Flowy::Result.failure(error_code: :bad, error_data: { value: n }) } }

  context 'when at least one element produces Success' do
    it 'returns a Flowy::Success' do
      result = [1, 2, 3].any_success { |n| n == 2 ? ok.call(n) : fail.call(n) }
      expect(result).to be_a(Flowy::Success)
    end

    it 'collects all partials in data[:results]' do
      result = [1, 2, 3].any_success { |n| n == 1 ? ok.call(n) : fail.call(n) }
      expect(result.data[:results].size).to eq(3)
    end

    it 'returns Success even when all partials are Success' do
      result = [1, 2, 3].any_success { |n| ok.call(n) }
      expect(result).to be_a(Flowy::Success)
      expect(result.data[:results]).to all(be_a(Flowy::Success))
    end
  end

  context 'when all elements produce Failure' do
    it 'returns a Flowy::Failure' do
      result = [1, 2, 3].any_success { |n| fail.call(n) }
      expect(result).to be_a(Flowy::Failure)
    end

    it 'uses :all_failed as the error_code' do
      result = [1, 2, 3].any_success { |n| fail.call(n) }
      expect(result.error_code).to eq(:all_failed)
    end

    it 'collects all partials in error_data[:results]' do
      result = [1, 2, 3].any_success { |n| fail.call(n) }
      expect(result.error_data[:results].size).to eq(3)
      expect(result.error_data[:results]).to all(be_a(Flowy::Failure))
    end
  end

  context 'on an empty collection' do
    it 'returns Failure (no successes) with an empty results array' do
      result = [].any_success { |n| ok.call(n) }
      expect(result).to be_a(Flowy::Failure)
      expect(result.error_code).to eq(:all_failed)
      expect(result.error_data[:results]).to eq([])
    end
  end

  context 'when the block returns an invalid type' do
    it 'raises TypeError' do
      expect {
        [1].any_success { |_n| 42 }
      }.to raise_error(TypeError, /all_success\/any_success block must return a Flowy::Result/)
    end
  end

  context 'on a generic Enumerable (not just Array)' do
    it 'works on a Range' do
      result = (1..3).any_success { |n| n == 2 ? ok.call(n) : fail.call(n) }
      expect(result).to be_a(Flowy::Success)
    end
  end
end
