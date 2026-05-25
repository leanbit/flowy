require 'spec_helper'

RSpec.describe Flowy do
  describe 'VERSION' do
    it 'is defined' do
      expect(Flowy::VERSION).not_to be_nil
    end

    it 'is a string in semver format' do
      expect(Flowy::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end

    it 'has the expected value' do
      expect(Flowy::VERSION).to eq('0.1.0')
    end
  end
end
