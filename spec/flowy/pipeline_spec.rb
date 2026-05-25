require 'spec_helper'

RSpec.describe Flowy::Pipeline do
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  let(:ok)   { ->(prev) { Flowy::Result.success(data: prev.data.merge(ok: true)) } }
  let(:fail) { ->(prev) { Flowy::Result.failure(error_code: :boom) } }

  # ---------------------------------------------------------------------------
  # Construction and immutability
  # ---------------------------------------------------------------------------
  describe '.new' do
    it 'starts empty' do
      expect(Flowy::Pipeline.new.empty?).to be true
    end

    it '#step returns a new instance without mutating the original' do
      original = Flowy::Pipeline.new
      augmented = original.step(:foo) { |p| Flowy::Result.success(data: p.data) }

      expect(original.size).to eq(0)
      expect(augmented.size).to eq(1)
    end

    it '#branch returns a new instance' do
      p1 = Flowy::Pipeline.new
      p2 = p1.branch(on: :kind) do |b|
        b.when(:a) { Flowy::Pipeline.new.step(:a) { |p| Flowy::Result.success(data: p.data) } }
      end

      expect(p1.size).to eq(0)
      expect(p2.size).to eq(1)
    end

    it '#step without a block accepts a Symbol name (symbolic step)' do
      expect { Flowy::Pipeline.new.step(:foo) }.not_to raise_error
    end

    it '#step without a block raises ArgumentError if the name is not a Symbol' do
      expect { Flowy::Pipeline.new.step('not a symbol') }.to raise_error(ArgumentError, /block or a Symbol name/)
    end

    it 'requires a block for #branch' do
      expect { Flowy::Pipeline.new.branch(on: :x) }.to raise_error(ArgumentError, /requires a block/)
    end

    it 'requires a block for #tap_step' do
      expect { Flowy::Pipeline.new.tap_step(:foo) }.to raise_error(ArgumentError, /requires a block/)
    end
  end

  # ---------------------------------------------------------------------------
  # Linear execution
  # ---------------------------------------------------------------------------
  describe '#call — linear pipeline' do
    it 'executes all steps and returns a Success' do
      pipeline = Flowy::Pipeline.new
        .step(:double) { |prev| Flowy::Result.success(data: { value: prev.data[:value] * 2 }) }
        .step(:inc)    { |prev| Flowy::Result.success(data: { value: prev.data[:value] + 1 }) }

      result = pipeline.call(starting_data: { value: 3 })

      expect(result).to be_success
      expect(result.data[:value]).to eq(7) # (3 * 2) + 1
    end

    it 'short-circuits on the first Failure and skips subsequent steps' do
      calls = []

      pipeline = Flowy::Pipeline.new
        .step(:a) { |prev| calls << :a; Flowy::Result.success(data: prev.data) }
        .step(:b) { |prev| calls << :b; Flowy::Result.failure(error_code: :stop) }
        .step(:c) { |prev| calls << :c; Flowy::Result.success(data: prev.data) }

      result = pipeline.call

      expect(result).to be_failure
      expect(result.error_code).to eq(:stop)
      expect(calls).to eq(%i[a b])
    end

    it 'an empty pipeline returns a Success with starting_data' do
      result = Flowy::Pipeline.new.call(starting_data: { x: 1 })

      expect(result).to be_success
      expect(result.data).to eq({ x: 1 })
    end
  end

  # ---------------------------------------------------------------------------
  # tap_step
  # ---------------------------------------------------------------------------
  describe '#tap_step' do
    it 'ignores the block return value and forwards the previous result' do
      side_effect = []

      pipeline = Flowy::Pipeline.new
        .step(:a) { |prev| Flowy::Result.success(data: { value: 42 }) }
        .tap_step(:log) do |prev|
          side_effect << prev.data[:value]
          Flowy::Result.failure(error_code: :should_be_ignored)
        end
        .step(:b) { |prev| Flowy::Result.success(data: prev.data.merge(done: true)) }

      result = pipeline.call

      expect(result).to be_success
      expect(result.data[:done]).to be true
      expect(side_effect).to eq([42])
    end

    it 'halts before the tap_step if the previous step returned a Failure' do
      calls = []

      pipeline = Flowy::Pipeline.new
        .step(:a) { |_| Flowy::Result.failure(error_code: :early) }
        .tap_step(:log) { |_| calls << :log }

      result = pipeline.call
      expect(result.error_code).to eq(:early)
      expect(calls).to be_empty
    end

    it 'accepts a tap_step block that returns a plain (non-Result) value' do
      pipeline = Flowy::Pipeline.new
        .step(:a)     { |prev| Flowy::Result.success(data: { value: 1 }) }
        .tap_step(:log) { |prev| 'side-effect only' }
        .step(:b)     { |prev| Flowy::Result.success(data: prev.data.merge(done: true)) }

      expect { pipeline.call }.not_to raise_error
      expect(pipeline.call.data).to include(value: 1, done: true)
    end

    it 'accepts a tap_step block that returns nil' do
      pipeline = Flowy::Pipeline.new
        .tap_step(:audit) { |_| nil }
        .step(:work)      { |prev| Flowy::Result.success(data: prev.data.merge(ok: true)) }

      result = pipeline.call(starting_data: { n: 1 })
      expect(result).to be_success
      expect(result.data).to include(n: 1, ok: true)
    end
  end

  # ---------------------------------------------------------------------------
  # Branch — dispatch by Symbol key
  # ---------------------------------------------------------------------------
  describe '#branch — dispatch via Symbol key' do
    let(:base_pipeline) do
      Flowy::Pipeline.new
        .step(:prepare) { |prev| Flowy::Result.success(data: prev.data.merge(prepared: true)) }
        .branch(on: :method) do |b|
          b.when(:fast) do
            Flowy::Pipeline.new.step(:fast_path) { |prev|
              Flowy::Result.success(data: prev.data.merge(path: :fast))
            }
          end
          b.when(:slow) do
            Flowy::Pipeline.new.step(:slow_path) { |prev|
              Flowy::Result.success(data: prev.data.merge(path: :slow))
            }
          end
          b.otherwise do
            Flowy::Pipeline.new.step(:default_path) { |prev|
              Flowy::Result.success(data: prev.data.merge(path: :default))
            }
          end
        end
        .step(:finalize) { |prev| Flowy::Result.success(data: prev.data.merge(finalized: true)) }
    end

    it 'routes to the correct branch (:fast)' do
      result = base_pipeline.call(starting_data: { method: :fast })
      expect(result).to be_success
      expect(result.data[:path]).to eq(:fast)
      expect(result.data[:prepared]).to be true
      expect(result.data[:finalized]).to be true
    end

    it 'routes to the correct branch (:slow)' do
      result = base_pipeline.call(starting_data: { method: :slow })
      expect(result).to be_success
      expect(result.data[:path]).to eq(:slow)
    end

    it 'uses otherwise as a fallback for unknown keys' do
      result = base_pipeline.call(starting_data: { method: :unknown })
      expect(result).to be_success
      expect(result.data[:path]).to eq(:default)
    end

    it 'returns :unmatched_branch when there is no otherwise and the key does not match' do
      pipeline = Flowy::Pipeline.new
        .branch(on: :kind) do |b|
          b.when(:x) { Flowy::Pipeline.new.step(:x) { |p| Flowy::Result.success(data: p.data) } }
        end

      result = pipeline.call(starting_data: { kind: :unknown })
      expect(result).to be_failure
      expect(result.error_code).to eq(:unmatched_branch)
    end

    it 'propagates the Failure produced by the branch sub-pipeline' do
      pipeline = Flowy::Pipeline.new
        .branch(on: :kind) do |b|
          b.when(:bad) { Flowy::Pipeline.new.step(:x) { |_| Flowy::Result.failure(error_code: :sub_fail) } }
        end

      result = pipeline.call(starting_data: { kind: :bad })
      expect(result).to be_failure
      expect(result.error_code).to eq(:sub_fail)
    end

    it 'halts before the branch if a prior step returned a Failure' do
      pipeline = Flowy::Pipeline.new
        .step(:a) { |_| Flowy::Result.failure(error_code: :early) }
        .branch(on: :kind) do |b|
          b.when(:x) { Flowy::Pipeline.new.step(:x) { |p| Flowy::Result.success(data: p.data) } }
        end

      result = pipeline.call(starting_data: { kind: :x })
      expect(result.error_code).to eq(:early)
    end
  end

  # ---------------------------------------------------------------------------
  # Branch — dispatch via Lambda
  # ---------------------------------------------------------------------------
  describe '#branch — dispatch via Lambda' do
    it 'uses the lambda to compute the dispatch key' do
      pipeline = Flowy::Pipeline.new
        .branch(on: ->(data) { data[:amount] > 100 ? :high : :low }) do |b|
          b.when(:high) { Flowy::Pipeline.new.step(:h) { |p| Flowy::Result.success(data: p.data.merge(tier: :high)) } }
          b.when(:low)  { Flowy::Pipeline.new.step(:l) { |p| Flowy::Result.success(data: p.data.merge(tier: :low)) } }
        end

      expect(pipeline.call(starting_data: { amount: 200 }).data[:tier]).to eq(:high)
      expect(pipeline.call(starting_data: { amount: 50 }).data[:tier]).to eq(:low)
    end
  end

  # ---------------------------------------------------------------------------
  # Composition with >>
  # ---------------------------------------------------------------------------
  describe '#>> — sequential composition' do
    it 'concatenates two pipelines and executes them in sequence' do
      p1 = Flowy::Pipeline.new.step(:a) { |prev| Flowy::Result.success(data: prev.data.merge(a: 1)) }
      p2 = Flowy::Pipeline.new.step(:b) { |prev| Flowy::Result.success(data: prev.data.merge(b: 2)) }

      result = (p1 >> p2).call
      expect(result.data).to include(a: 1, b: 2)
    end

    it 'is associative: (p1 >> p2) >> p3 == p1 >> (p2 >> p3)' do
      step_proc = ->(key) { ->(prev) { Flowy::Result.success(data: prev.data.merge(key => true)) } }
      p1 = Flowy::Pipeline.new.step(:a, &step_proc.(:a))
      p2 = Flowy::Pipeline.new.step(:b, &step_proc.(:b))
      p3 = Flowy::Pipeline.new.step(:c, &step_proc.(:c))

      left  = (p1 >> p2) >> p3
      right = p1 >> (p2 >> p3)

      expect(left.call.data).to eq(right.call.data)
    end

    it 'short-circuits on the first Failure even across the composition boundary' do
      p1 = Flowy::Pipeline.new.step(:fail) { |_| Flowy::Result.failure(error_code: :stop) }
      p2 = Flowy::Pipeline.new.step(:never) { |_| raise "should never be called" }

      result = (p1 >> p2).call
      expect(result.error_code).to eq(:stop)
    end

    it 'does not mutate either of the original pipelines' do
      p1 = Flowy::Pipeline.new.step(:a) { |p| Flowy::Result.success(data: p.data) }
      p2 = Flowy::Pipeline.new.step(:b) { |p| Flowy::Result.success(data: p.data) }
      p1 >> p2

      expect(p1.size).to eq(1)
      expect(p2.size).to eq(1)
    end

    it 'raises TypeError when the right-hand operand is not a Pipeline' do
      p1 = Flowy::Pipeline.new
      expect { p1 >> :not_a_pipeline }.to raise_error(TypeError, /Flowy::Pipeline/)
    end
  end

  # ---------------------------------------------------------------------------
  # rescue_errors
  # ---------------------------------------------------------------------------
  describe 'rescue_errors: true' do
    it 'converts an unhandled exception into a Failure' do
      pipeline = Flowy::Pipeline.new
        .step(:boom) { |_| raise RuntimeError, "fire" }

      result = pipeline.call(rescue_errors: true)
      expect(result).to be_failure
      expect(result.error_code).to eq(:step_raised_error)
      expect(result.error_data[:message]).to eq("fire")
    end

    it 'without rescue_errors, the exception propagates' do
      pipeline = Flowy::Pipeline.new
        .step(:boom) { |_| raise RuntimeError, "fire" }

      expect { pipeline.call }.to raise_error(RuntimeError, "fire")
    end
  end

  # ---------------------------------------------------------------------------
  # TypeError for invalid return values
  # ---------------------------------------------------------------------------
  describe 'result validation' do
    it 'raises TypeError when a step does not return a Flowy::Result' do
      pipeline = Flowy::Pipeline.new
        .step(:bad) { |_| "a plain string" }

      expect { pipeline.call }.to raise_error(TypeError, /must return a Flowy::Success or Flowy::Failure/)
    end

    it 'raises TypeError when a branch value is not a Pipeline' do
      pipeline = Flowy::Pipeline.new
        .branch(on: :kind) do |b|
          b.when(:x) { "not a pipeline" }
        end

      expect { pipeline.call(starting_data: { kind: :x }) }.to raise_error(TypeError, /Flowy::Pipeline/)
    end
  end

  # ---------------------------------------------------------------------------
  # Introspection
  # ---------------------------------------------------------------------------
  describe '#steps' do
    it 'returns step metadata in order' do
      pipeline = Flowy::Pipeline.new
        .step(:validate)   { |p| Flowy::Result.success(data: p.data) }
        .tap_step(:log)    { |p| nil }
        .step(:persist)    { |p| Flowy::Result.success(data: p.data) }

      names = pipeline.steps.map { |s| s[:name] }
      types = pipeline.steps.map { |s| s[:type] }

      expect(names).to eq(%i[validate log persist])
      expect(types).to eq(%i[step tap_step step])
    end

    it 'branch nodes have type: :branch in the introspection output' do
      pipeline = Flowy::Pipeline.new
        .branch(on: :kind) do |b|
          b.when(:x) { Flowy::Pipeline.new.step(:x) { |p| Flowy::Result.success(data: p.data) } }
        end

      expect(pipeline.steps.first[:type]).to eq(:branch)
    end
  end

  # ---------------------------------------------------------------------------
  # Symbolic steps (resolved against context)
  # ---------------------------------------------------------------------------
  describe 'symbolic steps' do
    let(:context_class) do
      Class.new do
        def enrich(previous_result:)
          Flowy::Result.success(data: previous_result.data.merge(enriched: true))
        end

        def finalize(previous_result:)
          Flowy::Result.success(data: previous_result.data.merge(finalized: true))
        end
      end
    end

    it 'resolves a Symbol step against the context at call time' do
      pipeline = Flowy::Pipeline.new.step(:enrich)
      result   = pipeline.call(starting_data: { x: 1 }, context: context_class.new)

      expect(result).to be_success
      expect(result.data).to include(x: 1, enriched: true)
    end

    it 'supports mixing symbolic steps and block steps in the same pipeline' do
      pipeline = Flowy::Pipeline.new
        .step(:enrich)
        .step(:double) { |prev| Flowy::Result.success(data: prev.data.merge(doubled: true)) }
        .step(:finalize)

      result = pipeline.call(starting_data: {}, context: context_class.new)
      expect(result.data).to include(enriched: true, doubled: true, finalized: true)
    end

    it 'raises ArgumentError when invoked without a context' do
      pipeline = Flowy::Pipeline.new.step(:enrich)
      expect { pipeline.call }.to raise_error(ArgumentError, /symbolic step :enrich requires a `context:`/)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration with Flowy::Concern
  # ---------------------------------------------------------------------------
  describe 'integration with Flowy::Concern' do
    it 'a Pipeline can be used as an inline step in run_steps' do
      sub_pipeline = Flowy::Pipeline.new
        .step(:enrich) { |prev| Flowy::Result.success(data: prev.data.merge(enriched: true)) }

      klass = Class.new do
        include Flowy::Concern

        define_method(:call) do
          run_steps(
            starting_data: { value: 1 },
            steps: [sub_pipeline]
          )
        end
      end

      result = klass.new.call
      expect(result).to be_success
      expect(result.data[:enriched]).to be true
    end

    it 'a Pipeline used in a Concern short-circuits correctly on Failure' do
      sub_pipeline = Flowy::Pipeline.new
        .step(:fail) { |_| Flowy::Result.failure(error_code: :inner_fail) }
        .step(:never) { |_| raise "should never run" }

      klass = Class.new do
        include Flowy::Concern
        define_method(:call) { run_steps(starting_data: {}, steps: [sub_pipeline]) }
      end

      result = klass.new.call
      expect(result.error_code).to eq(:inner_fail)
    end

    it 'a Pipeline declared via .step DSL is executed in the flow' do
      sub_pipeline = Flowy::Pipeline.new
        .step(:add_flag) { |prev| Flowy::Result.success(data: prev.data.merge(flag: true)) }

      klass = Class.new do
        include Flowy::Concern
        step sub_pipeline
        def call = run_steps(starting_data: { x: 1 })
      end

      result = klass.new.call
      expect(result).to be_success
      expect(result.data[:flag]).to be true
    end
  end
end
